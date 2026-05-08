"""
Return whether two file stamps describe the same file contents.
"""
function same_stamp(a::FileStamp, b::FileStamp)
    return a.mtime == b.mtime && a.size == b.size && a.hash == b.hash
end

"""
Parse source text according to `parse_as`.
"""
function parse_source_blocks(
    text::AbstractString,
    line_starts::Vector{Int},
    parse_as::Symbol;
    path::AbstractString="<memory>",
)
    parse_as == :julia && return parse_julia_blocks(text, line_starts; path=path)
    parse_as == :text && return parse_text_blocks(text, line_starts)
    throw(ArgumentError("parse_as must resolve to :julia or :text"))
end

"""
Create handle records for all parsed blocks in `cache`.
"""
function intern_blocks!(cache::FileCache, display_path::AbstractString)
    handle_ids = Int[]

    for (index, block) in pairs(cache.blocks)
        record = HandleRecord(
            cache.key,
            String(display_path),
            index,
            block.span,
            block.lines,
            span_text(cache.text, block.span),
            nothing,
            true,
        )
        handle = register_handle!(record)
        push!(handle_ids, handle.id)
    end

    cache.handles = handle_ids
    return cache
end

"""
Build a new cache entry for an existing file.
"""
function build_file_cache!(
    key::FileKey,
    path::AbstractString,
    display_path::AbstractString,
    parse_as::Symbol,
)
    info = read_source_file(path)
    blocks = parse_source_blocks(info.text, info.line_starts, parse_as; path=String(path))

    cache = FileCache(
        key,
        info.id,
        String(path),
        Set([String(path)]),
        info.stamp,
        parse_as,
        info.text,
        info.line_starts,
        info.line_ending,
        blocks,
        Int[],
        1,
    )

    intern_blocks!(cache, display_path)
    return cache
end

"""
Replace a cache entry after a parse mode or external content change.
"""
function replace_file_cache!(
    key::FileKey,
    path::AbstractString,
    display_path::AbstractString,
    parse_as::Symbol,
)
    state = STATE[]
    old_cache = state.files[key]
    invalidate_file_handles!(key)
    cache = build_file_cache!(key, path, display_path, parse_as)
    cache.generation = old_cache.generation + 1
    cache.paths = union(old_cache.paths, Set([String(path)]))
    state.files[key] = cache
    state.path_index[String(path)] = key
    state.id_index[cache.current_id::FileID] = key
    return cache
end

"""
Load and parse a file, returning its cache entry.
"""
function load_file(path::AbstractString; parse_as::Symbol=:auto)
    abs_path = absolute_path(path)
    display_path = String(path)
    mode = parse_mode_for_path(abs_path; parse_as=parse_as)
    state = STATE[]

    if haskey(state.path_index, abs_path)
        key = state.path_index[abs_path]
        cache = state.files[key]
        info = read_source_file(abs_path)

        if cache.parse_as == mode && same_stamp(cache.stamp, info.stamp)
            push!(cache.paths, abs_path)
            state.id_index[info.id] = key
            return cache
        end

        return replace_file_cache!(key, abs_path, display_path, mode)
    end

    info = read_source_file(abs_path)
    if haskey(state.id_index, info.id)
        key = state.id_index[info.id]
        cache = state.files[key]

        if cache.parse_as == mode && same_stamp(cache.stamp, info.stamp)
            push!(cache.paths, abs_path)
            state.path_index[abs_path] = key
            return cache
        end

        return replace_file_cache!(key, abs_path, display_path, mode)
    end

    key = allocate_file_key!()
    cache = build_file_cache!(key, abs_path, display_path, mode)
    state.files[key] = cache
    state.path_index[abs_path] = key
    state.id_index[cache.current_id::FileID] = key
    return cache
end

"""
Return the public handle for a parsed block in a cache entry.
"""
function block_handle(cache::FileCache, block_index::Integer)
    return Handle(cache.handles[block_index])
end
