"""
    VersionControl(path; kwargs...)
    VersionControl(nothing; kwargs...)

Version-control policy used by [`apply!`](@ref).

`VersionControl(path)` creates a git-backed policy rooted at `path` (or any path
inside the worktree). `VersionControl(nothing)` creates a no-version-control
policy. Keyword arguments are stored as defaults and forwarded to `apply!`;
common options include `require_view`, `require_versioning`, `require_clean`,
`formatter`, and `default_message`.

Prefer the clearer aliases [`GitVersionControl`](@ref) and
[`NoVersionControl`](@ref) when the desired backend is known.
"""
struct VersionControl{T,S<:NamedTuple}
    vc_type::Val{T}
    repo_path::String
    kwargs::S
end

VersionControl(path::AbstractString; kwargs...) = VersionControl(Val(:git), abspath(path), (; kwargs...))
VersionControl(::Nothing; kwargs...) = VersionControl(Val(:none), "", (; kwargs...))

const NoVersionControl{S} = VersionControl{:none,S}
const GitVersionControl{S} = VersionControl{:git,S}

"""
    NoVersionControl(; kwargs...)

Create a policy that applies edits directly to the filesystem without staging or
committing changes. Keyword arguments are used as default `apply!` options.

This is useful for scratch files, generated files, and tests. Use
`NoVersionControl(require_view=true)` to still require a displayed diff before
writing files.
"""
NoVersionControl(; kwargs...) = VersionControl(nothing; kwargs...)

"""
    GitVersionControl(path; kwargs...)

Create a git-backed version-control policy for the worktree containing `path`.
Keyword arguments are used as default `apply!` options.

`path` is stored as an absolute path when the policy is constructed. 

When applied with a commit message, git-backed edits check versioning
requirements, stage affected paths, and create a commit for the edit.
"""
GitVersionControl(path::AbstractString; kwargs...) = VersionControl(path; kwargs...)

"""
Information about a git commit created while applying an edit.
"""
struct CommitInfo
    kind::Symbol
    id::String
    message::String
end

"""
Information about a file affected while applying an edit.

`path` is the resulting path. `original_path` is set for moves or renames.
`action` describes the filesystem effect, such as `:created`, `:modified`,
`:deleted`, `:moved`, or `:moved_modified`.
"""
struct FileChange
    path::String
    original_path::Union{Nothing,String}
    action::Symbol
end

"""
Result returned by `apply!`.

Contains the version-control mode used, affected files, commits created, the
applied diff text, and any paths changed by pre-apply formatting.
"""
struct ApplyResult
    vc::Symbol
    changes::Vector{FileChange}
    commits::Vector{CommitInfo}
    diff::String
    formatted_paths::Vector{String}
end

"""
Current identity of an existing filesystem object.
"""
struct FileID
    device::UInt64
    inode::UInt64
end

"""
Stable internal identity for a cached logical file.
"""
struct FileKey
    id::Int
end

"""
Half-open byte interval `[lo, hi)`.
"""
struct Span
    lo::Int
    hi::Int
end

"""
A parsed block of source or text.
"""
struct Block
    span::Span
    lines::UnitRange{Int}
    kind::Symbol
end

"""
Change detector for file contents.
"""
struct FileStamp
    mtime::Float64
    size::Int64
    hash::Vector{UInt8}
end

abstract type PathCondition end

struct MustExist <: PathCondition
    path::String
    stamp::FileStamp
end

struct MustNotExist <: PathCondition
    path::String
end

"""
Parsed representation of a logical cached file.
"""
mutable struct FileCache
    key::FileKey
    current_id::Union{Nothing,FileID}
    primary_path::String
    paths::Set{String}
    stamp::FileStamp
    parse_as::Symbol
    text::String
    line_starts::Vector{Int}
    line_ending::String
    blocks::Vector{Block}
    handles::Vector{Int}
    generation::Int
end

"""
    Handle(path, line[, pos=1]; parse_as=:auto)
    Handle(method)
    Handle(stackframe)

Reference to one parsed source or text block.

The file constructor loads `path` and returns the block containing the
1-based `(line, pos)` location. If the location falls between blocks, the next
block is returned; requesting the end-of-file location returns the EOF handle.
`parse_as` may be `:auto`, `:julia`, or `:text`.

Method and stack-frame constructors use Julia source-location metadata and return
an invalid handle when no source location is available. Test handles with
[`is_valid`](@ref) before using them when source information may be missing.
"""
struct Handle
    id::Int
end

"""
Mutable registry entry backing a Handle.
"""
mutable struct HandleRecord
    file::Union{Nothing,FileKey}
    path::String
    block_index::Int
    span::Span
    lines::UnitRange{Int}
    text::String
    doc::Union{Nothing,String}
    valid::Bool
end

"""
    AbstractEdit

Abstract supertype for all edit values.

Concrete edits describe source or filesystem changes without performing them.
They can be displayed to review the planned diff, validated with
[`is_valid`](@ref), combined with [`Combine`](@ref) or `*`, and applied with
[`apply!`](@ref).
"""
abstract type AbstractEdit end

"""
Placeholder for the displayed-plan fingerprint used by later apply planning.
"""
struct DisplayedPlan
    fingerprint::String
    valid::Bool
    text::String
end

"""
    Replace(handle, code)

Edit that replaces the block referenced by `handle` with `code`.

The replacement is planned against the current contents of the handle's file.
Applying the edit may invalidate or update handles that refer to affected
blocks.
"""
struct Replace <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    Delete(handle)

Edit that deletes the block referenced by `handle`.

Deleting an EOF handle is valid and has no effect.
"""
struct Delete <: AbstractEdit
    handle::Handle
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    InsertBefore(handle, code)

Edit that inserts `code` immediately before the block referenced by `handle`.
"""
struct InsertBefore <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    InsertAfter(handle, code)

Edit that inserts `code` immediately after the block referenced by `handle`.
"""
struct InsertAfter <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    CreateFile(path, code; parse_as=:auto)

Edit that creates a new file at `path` containing `code`.

`path` is stored as an absolute path when the edit is constructed. The file must
not already exist when the edit is applied. `parse_as` controls how handles in
the new file are parsed and may be `:auto`, `:julia`, or `:text`.
"""
struct CreateFile <: AbstractEdit
    path::String
    code::String
    parse_as::Symbol
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    MoveFile(old_path, new_path)

Edit that moves or renames a file from `old_path` to `new_path`.

Both paths are stored as absolute paths when the edit is constructed. The source
must exist and the destination must not exist when the edit is applied.
"""
struct MoveFile <: AbstractEdit
    old_path::String
    new_path::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    DeleteFile(path)

Edit that deletes the file at `path`.

The path is stored as an absolute path when the edit is constructed. Handles for
deleted files are invalidated after application.
"""
struct DeleteFile <: AbstractEdit
    path::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    Combine(edits...)
    Combine(edits::AbstractVector)

Edit that plans and applies several edits as one operation.

Edits are interpreted in order, so later edits see the virtual filesystem
produced by earlier edits. Validation succeeds or fails for the combined plan as
a unit. The `*` operator is shorthand for combining edits in left-to-right
order.
"""
struct Combine <: AbstractEdit
    edits::Vector{AbstractEdit}
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
Executable plan for one handle-based content replacement.
"""
struct ReplacementEditPlan
    edit::AbstractEdit
    key::FileKey
    path::String
    parse_as::Symbol
    stamp::FileStamp
    span::Span
    code::String
    old_text::String
    new_text::String
    target::Handle
    operation::Symbol
    valid::Bool
    errors::Vector{String}
    fingerprint::String
    display_text::String
end

"""
Final filesystem/content effect for one logical or path-only file.
"""
struct FileEditEffect
    key::Union{Nothing,FileKey}
    original_path::Union{Nothing,String}
    path::String
    parse_as::Symbol
    stamp::Union{Nothing,FileStamp}
    old_text::Union{Nothing,String}
    new_text::Union{Nothing,String}
    created::Bool
    deleted::Bool
    handle_spans::Dict{Int,Union{Nothing,Span}}
end

"""
Executable ordered edit plan for combined and file-level edits.
"""
struct EditPlan
    edit::AbstractEdit
    effects::Vector{FileEditEffect}
    moves::Vector{Tuple{String,String}}
    deletes::Vector{String}
    ordered_steps::Vector{String}
    valid::Bool
    errors::Vector{String}
    fingerprint::String
    display_text::String
end

mutable struct VirtualFileState
    key::Union{Nothing,FileKey}
    original_path::Union{Nothing,String}
    path::String
    parse_as::Symbol
    stamp::Union{Nothing,FileStamp}
    original_text::Union{Nothing,String}
    text::Union{Nothing,String}
    created::Bool
    deleted::Bool
    handle_spans::Dict{Int,Union{Nothing,Span}}
end

struct InterpretResult
    ok::Bool
    message::String
end
