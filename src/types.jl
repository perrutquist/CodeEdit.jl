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
Reference to a source/text block.
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
