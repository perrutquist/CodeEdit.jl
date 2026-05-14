const _refreshing_file_keys = Set{FileKey}()

"""
Refresh a handle's backing cache if the file changed externally.
"""
function refresh_handle!(handle::Handle)
    record = handle_record(handle)

    if record === nothing || !record.valid || record.file === nothing
        return record
    end

    state = STATE[]
    cache = get(state.files, record.file, nothing)
    cache === nothing && return record

    if cache.key in _refreshing_file_keys
        return record
    end

    if !isfile(cache.primary_path)
        remove_file_cache!(cache.key)
        return record
    end

    info = read_source_file(cache.primary_path)

    if same_file_contents(cache.stamp, info.stamp)
        cache.stamp = info.stamp
        return record
    end

    push!(_refreshing_file_keys, cache.key)

    try
        reindex(cache.primary_path)
    finally
        delete!(_refreshing_file_keys, cache.key)
    end

    return get(STATE[].handles, handle.id, nothing)
end

"""
Throw if `handle` is invalid, otherwise return its handle record.
"""
function valid_handle_record(handle::Handle)
    record = refresh_handle!(handle)
    (record === nothing || !record.valid) && throw(ArgumentError("invalid handle"))
    return record
end

"""
    is_valid(handle)
    is_valid(edit)

Return whether a handle currently refers to a valid block, or whether an edit
can be applied without validation errors.
"""
function is_valid end

function is_valid(handle::Handle)
    record = refresh_handle!(handle)
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
Return the parse mode associated with a valid handle, or `nothing` for an
invalid handle.
"""
function handle_parse_as(handle::Handle)
    record = refresh_handle!(handle)

    if record === nothing || !record.valid || record.file === nothing
        return nothing
    end

    cache = get(STATE[].files, record.file, nothing)
    cache === nothing && return nothing
    return cache.parse_as
end

"""
Return whether a handle was parsed as Julia source.
"""
function is_julia(handle::Handle)
    return handle_parse_as(handle) == :julia
end

"""
Return whether a handle was parsed as plain text.
"""
function is_text(handle::Handle)
    return handle_parse_as(handle) == :text
end

"""
Return whether a handle's filepath matches `regex`.
"""
function filepath_matches(handle::Handle, regex::Regex)
    is_valid(handle) || return false
    return occursin(regex, filepath(handle))
end

filepath_matches(regex::Regex, handle::Handle) = filepath_matches(handle, regex)

filepath_matches(regex::Regex) = Base.Fix2(filepath_matches, regex)

"""
Return whether `text` begins with a Julia string literal docstring prefix.
"""
function leading_julia_string_literal(text::AbstractString)
    stripped = lstrip(text)
    isempty(stripped) && return nothing

    if startswith(stripped, "\"\"\"")
        stop = findnext("\"\"\"", stripped, nextind(stripped, nextind(stripped, nextind(stripped, firstindex(stripped)))))
        stop === nothing && return nothing
        content_start = nextind(stripped, nextind(stripped, nextind(stripped, firstindex(stripped))))
        content_stop = prevind(stripped, stop)
        rest_start = nextind(stripped, nextind(stripped, nextind(stripped, stop)))
        return (
            text = content_start > content_stop ? "" : String(stripped[content_start:content_stop]),
            rest = rest_start > ncodeunits(stripped) ? "" : String(stripped[rest_start:end]),
        )
    end

    startswith(stripped, "\"") || return nothing
    index = nextind(stripped, firstindex(stripped))
    escaped = false

    while index <= ncodeunits(stripped)
        char = stripped[index]

        if escaped
            escaped = false
        elseif char == '\\'
            escaped = true
        elseif char == '"'
            content_start = nextind(stripped, firstindex(stripped))
            content_stop = prevind(stripped, index)
            rest_start = nextind(stripped, index)
            return (
                text = content_start > content_stop ? "" : String(stripped[content_start:content_stop]),
                rest = rest_start > ncodeunits(stripped) ? "" : String(stripped[rest_start:end]),
            )
        end

        index = nextind(stripped, index)
    end

    return nothing
end

"""
Return a handle's docstring text, if available.
"""
function docstring(handle::Handle)
    record = valid_handle_record(handle)
    record.doc !== nothing && return record.doc

    docs = String[]
    rest = record.text

    while true
        literal = leading_julia_string_literal(rest)
        literal === nothing && break
        push!(docs, literal.text)
        rest = literal.rest
        isempty(strip(rest)) && break
    end

    record.doc = isempty(docs) ? nothing : join(docs, "\n")
    return record.doc
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
Return statically resolvable include paths in a parsed Julia cache.
"""
function included_paths(cache::FileCache)
    cache.parse_as == :julia || return String[]

    result = String[]
    include_pattern = r"^\s*include\(\s*([\"'])(.*?)\1\s*\)\s*$"m

    for block in cache.blocks
        block.kind == :eof && continue
        source = span_text(cache.text, block.span)

        for match in eachmatch(include_pattern, source)
            path = joinpath(dirname(cache.primary_path), match.captures[2])
            isfile(path) && push!(result, absolute_path(path))
        end
    end

    return result
end

function collect_handles!(
    result::Set{Handle},
    path::AbstractString,
    includes::Bool,
    parse_as::Symbol,
    seen::Set{String},
)
    cache = load_file(path; parse_as=parse_as)
    abs_path = cache.primary_path
    abs_path in seen && return result
    push!(seen, abs_path)
    union!(result, Set(Handle.(cache.handles)))

    if includes
        for included in included_paths(cache)
            collect_handles!(result, included, true, :auto, seen)
        end
    end

    return result
end

"""
    handles(path; includes=false, parse_as=:auto)
    handles(paths; includes=false, parse_as=:auto)
    handles(root, pattern; includes=false, parse_as=:auto)

Return handles for all parsed blocks in one file, a collection of files, or
files under `root` matching `pattern`.

If `includes=true`, statically resolvable Julia `include(...)` paths are
followed recursively. `parse_as` may be `:auto`, `:julia`, or `:text`.
"""
function handles end

function handles(path::AbstractString; includes::Bool=false, parse_as::Symbol=:auto)
    return collect_handles!(Set{Handle}(), path, includes, parse_as, Set{String}())
end

function handles(paths; includes::Bool=false, parse_as::Symbol=:auto)
    result = Set{Handle}()

    for path in paths
        union!(result, handles(path; includes=includes, parse_as=parse_as))
    end

    return result
end

function handles(root::AbstractString, pattern::AbstractString; includes::Bool=false, parse_as::Symbol=:auto)
    return handles(glob(pattern, root); includes=includes, parse_as=parse_as)
end
