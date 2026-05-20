"""
Version-control specification used by `apply!`.

`vc_type` is typically `Val(:git)` or `Val(:none)`. `kwargs` stores default
keyword arguments for later `apply!` calls.
"""
struct VersionControl{T,S<:NamedTuple}
    vc_type::Val{T}
    repo_path::String
    kwargs::S
end

VersionControl(path::AbstractString; kwargs...) = VersionControl(Val(:git), String(path), (; kwargs...))
VersionControl(::Nothing; kwargs...) = VersionControl(Val(:none), "", (; kwargs...))

const NoVersionControl{S} = VersionControl{:none,S}
const GitVersionControl{S} = VersionControl{:git,S}

"""
A "version control" specification that uses no version control.
""" 
NoVersionControl(; kwargs...) = VersionControl(nothing; kwargs...)

"""
A git version control specification.
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
    Handle(path, line, pos=1; parse_as=:auto)
    Handle(method)
    Handle(stackframe)

Reference to a parsed source/text block.

The path-based constructor returns a handle to the block containing `(line, pos)`,
or to the next block after that location. The method-based constructor returns a
handle to a method definition when source information is available.
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

Edit objects describe source or filesystem changes that can be displayed,
validated, and then applied with [`apply!`](@ref).
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
    Replace(handle::Handle, code::AbstractString)

Edit that replaces the source block referred to by `handle` with `code`.
"""
struct Replace <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    Delete(handle::Handle)

Edit that deletes the source block referred to by `handle`.

Deleting an EOF handle has no effect.
"""
struct Delete <: AbstractEdit
    handle::Handle
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    InsertBefore(handle::Handle, code::AbstractString)

Edit that inserts `code` immediately before the source block referred to by
`handle`.
"""
struct InsertBefore <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    InsertAfter(handle::Handle, code::AbstractString)

Edit that inserts `code` immediately after the source block referred to by
`handle`.
"""
struct InsertAfter <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    CreateFile(path::AbstractString, code::AbstractString; parse_as::Symbol=:auto)

Edit that creates a new file at `path` containing `code`.

`parse_as` may be `:auto`, `:julia`, or `:text`.
"""
struct CreateFile <: AbstractEdit
    path::String
    code::String
    parse_as::Symbol
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    MoveFile(old_path::AbstractString, new_path::AbstractString)

Edit that moves or renames a file from `old_path` to `new_path`.
"""
struct MoveFile <: AbstractEdit
    old_path::String
    new_path::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    DeleteFile(path::AbstractString)

Edit that deletes the file at `path`.
"""
struct DeleteFile <: AbstractEdit
    path::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    Combine(edits::AbstractEdit...)
    Combine(edits::AbstractVector{<:AbstractEdit})

Edit that combines multiple edits into one planned operation.

Combined edits are interpreted in order and validated as a unit. Applying a
combined edit that touches multiple files is best-effort at the filesystem
level, so a later filesystem failure can leave earlier operations applied.
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
