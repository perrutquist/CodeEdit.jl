const _refreshing_file_keys = Set{FileKey}()

const invalid_handle = Handle(0)

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

Return whether `handle` currently refers to a valid parsed block, or whether
`edit` can be planned without validation errors.

Handles may become invalid after file edits, file deletion, or external changes
that cannot be matched during reindexing. For edits, this performs planning but
does not write to the filesystem.
"""
function is_valid(handle::Handle)
    record = refresh_handle!(handle)
    return record !== nothing && record.valid
end

"""
    filepath(handle)

Return the absolute path of the file containing `handle`.

Throws `ArgumentError` if the handle is invalid.
"""
function filepath(handle::Handle)
    return valid_handle_record(handle).path
end

"""
    lines(handle)

Return the 1-based line range covered by `handle`.

Throws `ArgumentError` if the handle is invalid.
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
    is_julia(handle)

Return `true` if `handle` is valid and its file was parsed as Julia source.
"""
function is_julia(handle::Handle)
    return handle_parse_as(handle) == :julia
end

"""
    is_text(handle)

Return `true` if `handle` is valid and its file was parsed as plain text.
"""
function is_text(handle::Handle)
    return handle_parse_as(handle) == :text
end

"""
    filepath_matches(handle, regex)
    filepath_matches(regex, handle)
    filepath_matches(regex)

Return whether `handle` is valid and its filepath matches `regex`.

The one-argument form returns a predicate suitable for `filter`, `search`
pipelines, and set comprehensions.
"""
function filepath_matches(handle::Handle, regex::Regex)
    is_valid(handle) || return false
    return occursin(regex, filepath(handle))
end

filepath_matches(regex::Regex, handle::Handle) = filepath_matches(handle, regex)

filepath_matches(regex::Regex) = Base.Fix2(filepath_matches, regex)

function _parse_handle_at_key(key::AbstractString)
    text = String(key)
    parts = split(text, ':')

    if length(parts) < 2
        throw(ArgumentError("handle key must have form \"path:line\" or \"path:line:pos\": \"$text\""))
    end

    last_number = tryparse(Int, parts[end])

    if last_number === nothing
        throw(ArgumentError("handle key must end with a numeric line or line:pos: \"$text\""))
    end

    line = last_number
    pos = nothing
    path_parts = parts[1:(end - 1)]

    if length(parts) >= 3
        previous_number = tryparse(Int, parts[end - 1])

        if previous_number !== nothing
            line = previous_number
            pos = last_number
            path_parts = parts[1:(end - 2)]
        end
    end

    path_suffix = join(path_parts, ":")

    isempty(path_suffix) && throw(ArgumentError("handle key path suffix is empty: \"$text\""))
    line < 1 && throw(ArgumentError("handle key line must be positive: \"$text\""))
    pos !== nothing && pos < 1 && throw(ArgumentError("handle key position must be positive: \"$text\""))

    return (path_suffix, line, pos)
end

function _handle_at_query(path_suffix::AbstractString, line::Integer, pos)
    return pos === nothing ? "$path_suffix:$line" : "$path_suffix:$line:$pos"
end

function _handle_touches_location(handle::Handle, line::Integer, pos)
    line in lines(handle) || return false
    pos === nothing && return true

    record = valid_handle_record(handle)
    record.file === nothing && return false
    cache = get(STATE[].files, record.file, nothing)
    cache === nothing && return false

    offset = try
        byte_offset_for_line_pos(cache.text, cache.line_starts, line, pos)
    catch err
        err isa ArgumentError || rethrow()
        throw(ArgumentError("character position is outside line bounds in $(filepath(handle)): $pos"))
    end

    return record.span.lo <= offset < record.span.hi
end

"""
    handle_at(handles, key)
    handle_at(handles, path_suffix, line[, pos])

Return the unique valid handle selected by file suffix and source location.

`key` must be `"path:line"` or `"path:line:pos"`. `path_suffix` is matched
against the end of each handle's filepath. Without `pos`, the selected block
must touch `line`; with `pos`, the block must contain that exact character
position on the line.

Throws `ArgumentError` if no path matches, the path suffix is ambiguous, no
block covers the requested location, or multiple blocks match.
"""
function handle_at(handles::AbstractSet{Handle}, key::AbstractString)
    path_suffix, line, pos = _parse_handle_at_key(key)
    return handle_at(handles, path_suffix, line, pos)
end

function handle_at(handles::AbstractSet{Handle}, path_suffix::AbstractString, line::Integer, pos=nothing)
    line < 1 && throw(ArgumentError("line must be positive: $line"))
    pos !== nothing && pos < 1 && throw(ArgumentError("position must be positive: $pos"))

    matching_paths = Set{String}()

    for handle in handles
        is_valid(handle) || continue
        path = filepath(handle)
        endswith(path, path_suffix) && push!(matching_paths, path)
    end

    paths = sort!(collect(matching_paths))
    query = _handle_at_query(path_suffix, line, pos)

    if isempty(paths)
        throw(ArgumentError("no filepath ending in \"$path_suffix\" among handles"))
    elseif length(paths) > 1
        throw(ArgumentError("ambiguous filepath suffix \"$path_suffix\" matched: $(join(paths, ", "))"))
    end

    path = paths[1]
    matches = Handle[]

    for handle in handles
        is_valid(handle) || continue
        filepath(handle) == path || continue
        _handle_touches_location(handle, line, pos) && push!(matches, handle)
    end

    if isempty(matches)
        throw(ArgumentError("no handle matching \"$query\""))
    elseif length(matches) > 1
        throw(ArgumentError("ambiguous handle location \"$query\" matched $(length(matches)) handles"))
    end

    return matches[1]
end

Base.getindex(handles::AbstractSet{Handle}, key::AbstractString) = handle_at(handles, key)

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
        content_stop = prevind(stripped, first(stop))
        rest_start = nextind(stripped, last(stop))
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
    docstring(handle)

Return leading Julia string-literal docstrings attached to `handle`, or
`nothing` if none are found.

Adjacent leading string literals are joined with newlines. Throws
`ArgumentError` if the handle is invalid.
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
    string(handle)

Return the source or text block referenced by `handle`.

Throws `ArgumentError` if the handle is invalid.
"""
function Base.string(handle::Handle)
    return valid_handle_record(handle).text
end

"""
Return whether `block` contains byte offset `offset`.
"""
function contains_offset(block::ParsedBlock, offset::Integer)
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

function Handle(path::AbstractString, line::Integer, pos::Integer=1; parse_as::Symbol=:auto, return_invalid=false)
    if !isfile(path)
        return_invalid && return invalid_handle
        throw(ArgumentError("source file could not be located: $path"))
    end

    cache = load_file(path; parse_as=parse_as)
    eof_lineno = eof_line(cache.text, cache.line_starts)

    if line == eof_lineno
        if pos != 1
           return_invalid && return invalid_handle
           throw(ArgumentError("character position is outside line bounds: $pos"))
        end
        return block_handle(cache, length(cache.blocks))
    end

    if isempty(cache.line_starts)
        return_invalid && return invalid_handle
        throw(ArgumentError("line is outside file bounds: $line"))
    end

    if !(1 <= line <= line_count(cache.line_starts))
        return_invalid && return invalid_handle
        throw(ArgumentError("line is outside file bounds: $line"))
    end
    offset = byte_offset_for_line_pos(cache.text, cache.line_starts, line, pos)
    return block_handle(cache, block_index_at_offset(cache, offset))
end

function Handle(::Nothing, line::Integer; return_invalid=true)
    return_invalid && return invalid_handle
    throw(ArgumentError("invalid source location"))
end

"""
Return a handle to the source block referenced by a stack frame when source
information is available.
"""
function Handle(sf::StackTraces.StackFrame; return_invalid=true)
    (path, line) = if sf.linfo isa Core.MethodInstance
        functionloc(sf.linfo.def)
    else
        (Base.find_source_file(Base.fixup_stdlib_path(string(sf.file))), Int32(sf.line))
    end
    Handle(path, line; return_invalid)
end

"""
Return a handle to a method definition when source information is available.
"""
function Handle(method::Method; return_invalid=true)
    (path, line) = functionloc(method)
    Handle(path, line; return_invalid)
end

"""
    eof_handle(path; parse_as=:auto)

Return a handle to the end-of-file block for `path`.

The EOF handle is useful as an insertion target when appending code. `parse_as`
may be `:auto`, `:julia`, or `:text`.
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
    handles(repo::VersionControl; includes=false, parse_as=:auto)
    handles(methods_or_stacktrace)

Return a `Set{Handle}` for parsed blocks from files, directories, repositories,
method lists, or stack traces.

`handles(root, pattern)` searches paths matched by `Glob.glob(pattern, root)`.
For git-backed `VersionControl` objects, only tracked UTF-8 files are scanned;
`NoVersionControl()` returns an empty set.

If `includes=true`, statically resolvable Julia `include(...)` calls are
followed recursively. `parse_as` may be `:auto`, `:julia`, or `:text`.
"""
function handles end

function handles(path::AbstractString; includes::Bool=false, parse_as::Symbol=:auto)
    return collect_handles!(Set{Handle}(), path, includes, parse_as, Set{String}())
end

function handles(paths::Vector{<:AbstractString}; includes::Bool=false, parse_as::Symbol=:auto)
    result = Set{Handle}()

    for path in paths
        union!(result, handles(path; includes=includes, parse_as=parse_as))
    end

    return result
end

function handles(root::AbstractString, pattern::AbstractString; includes::Bool=false, parse_as::Symbol=:auto)
    return handles(glob(pattern, root); includes=includes, parse_as=parse_as)
end

function handles(ml::Base.MethodList)
    Set(Handle(f) for f in ml)
end

function handles(sf::Vector{StackTraces.StackFrame})
    Set(Handle(f) for f in sf)
end

handles(trace::Vector{Union{Ptr{Nothing}, Base.InterpreterIP}}) = handles(stacktrace(trace))

"""
Sort key used when displaying collections of handles.
"""
function handle_sort_key(handle::Handle)
    record = handle_record(handle)

    if record === nothing || !record.valid
        return ("\uffff", typemax(Int), typemax(Int), handle.id)
    end

    return (handle_primary_path(record), record.span.lo, record.span.hi, handle.id)
end

function Base.isless(a::Handle, b::Handle)
    isless(handle_sort_key(a), handle_sort_key(b))
end
