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
