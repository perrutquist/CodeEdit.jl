"""
Throw if `handle` is invalid, otherwise return its handle record.
"""
function valid_handle_record(handle::Handle)
    record = handle_record(handle)
    (record === nothing || !record.valid) && throw(ArgumentError("invalid handle"))
    return record
end

"""
Return whether a handle currently refers to a valid block.
"""
function is_valid(handle::Handle)
    record = handle_record(handle)
    return record !== nothing && record.valid
end

"""
Return the path associated with a handle.
"""
function filepath(handle::Handle)
    return valid_handle_record(handle).path
end

"""
Return the line range associated with a handle.
"""
function lines(handle::Handle)
    return valid_handle_record(handle).lines
end

"""
Return a handle's cached docstring text, if available.
"""
function docstring(handle::Handle)
    return valid_handle_record(handle).doc
end

"""
Return the source/text block associated with a handle.
"""
function Base.string(handle::Handle)
    return valid_handle_record(handle).text
end

"""
Return whether `block` contains byte offset `offset`.
"""
function contains_offset(block::Block, offset::Integer)
    return block.span.lo <= offset < block.span.hi
end

"""
Return the parsed block index matching a byte offset, or the next block after it.
"""
function block_index_at_offset(cache::FileCache, offset::Integer)
    for (index, block) in pairs(cache.blocks)
        contains_offset(block, offset) && return index
        offset < block.span.lo && return index
    end

    return length(cache.blocks)
end

"""
Return a handle to the block containing `(line, pos)`, or the next block.
"""
function Handle(path::AbstractString, line::Integer, pos::Integer=1; parse_as::Symbol=:auto)
    cache = load_file(path; parse_as=parse_as)
    eof_lineno = eof_line(cache.text, cache.line_starts)

    if line == eof_lineno
        pos == 1 || throw(ArgumentError("character position is outside line bounds: $pos"))
        return block_handle(cache, length(cache.blocks))
    end

    if isempty(cache.line_starts)
        throw(ArgumentError("line is outside file bounds: $line"))
    end

    1 <= line <= line_count(cache.line_starts) || throw(ArgumentError("line is outside file bounds: $line"))
    offset = byte_offset_for_line_pos(cache.text, cache.line_starts, line, pos)
    return block_handle(cache, block_index_at_offset(cache, offset))
end

"""
Return the EOF handle for a file.
"""
function eof_handle(path::AbstractString; parse_as::Symbol=:auto)
    cache = load_file(path; parse_as=parse_as)
    return block_handle(cache, length(cache.blocks))
end

"""
Return all handles for a file.
"""
function handles(path::AbstractString; includes::Bool=false, parse_as::Symbol=:auto)
    cache = load_file(path; parse_as=parse_as)
    return Set(Handle.(cache.handles))
end

"""
Return all handles for a collection of paths.
"""
function handles(paths; includes::Bool=false, parse_as::Symbol=:auto)
    result = Set{Handle}()

    for path in paths
        union!(result, handles(path; includes=includes, parse_as=parse_as))
    end

    return result
end

"""
Return all handles for files under `root` matching `pattern`.
"""
function handles(root::AbstractString, pattern::AbstractString; includes::Bool=false, parse_as::Symbol=:auto)
    return handles(glob(pattern, root); includes=includes, parse_as=parse_as)
end
