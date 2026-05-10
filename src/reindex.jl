"""
Return the length of the longest common subsequence of two strings.
"""
function lcs_length(a::AbstractString, b::AbstractString)
    ac = collect(a)
    bc = collect(b)

    isempty(ac) && return 0
    isempty(bc) && return 0

    previous = zeros(Int, length(bc) + 1)
    current = zeros(Int, length(bc) + 1)

    for ca in ac
        for (j, cb) in pairs(bc)
            current[j + 1] = ca == cb ? previous[j] + 1 : max(previous[j + 1], current[j])
        end

        previous, current = current, previous
        fill!(current, 0)
    end

    return previous[end]
end

"""
Return a simple deterministic score for matching old and new blocks.
"""
function reindex_match_score(old_text::AbstractString, old_lines::UnitRange{Int}, block::Block, new_text::AbstractString)
    candidate_text = span_text(new_text, block.span)
    line_penalty = abs(old_lines.start - block.lines.start) + abs(old_lines.stop - block.lines.stop)

    if old_text == candidate_text
        return 10_000 - line_penalty
    end

    old_chars = length(old_text)
    candidate_chars = length(candidate_text)

    if old_chars == 0 || candidate_chars == 0
        return -line_penalty
    end

    common = lcs_length(old_text, candidate_text)
    similarity = 2 * common / (old_chars + candidate_chars)

    similarity >= 0.60 || return -line_penalty
    return floor(Int, 1_000 * similarity) - line_penalty
end

"""
    reindex(path)
    reindex()

Reparse cached files and conservatively preserve handles for uniquely matched
blocks.

The path form reindexes one cached file. The zero-argument form reindexes all
cached files that still exist.
"""
function reindex end

function reindex_file!(key::FileKey, abs_path::AbstractString)
    path = String(abs_path)
    state = STATE[]
    haskey(state.files, key) || return nothing

    old_cache = state.files[key]
    old_records = Dict(id => state.handles[id] for id in old_cache.handles if haskey(state.handles, id))
    info = read_source_file(path)

    if old_cache.current_id !== nothing && old_cache.current_id != info.id
        if get(state.id_index, old_cache.current_id, nothing) == key
            delete!(state.id_index, old_cache.current_id)
        end

        return replace_file_cache!(key, path, path, old_cache.parse_as, info)
    end

    blocks = parse_source_blocks(info.text, info.line_starts, old_cache.parse_as; path=path)

    cache = FileCache(
        key,
        info.id,
        path,
        union(old_cache.paths, Set([path])),
        info.stamp,
        old_cache.parse_as,
        info.text,
        info.line_starts,
        info.line_ending,
        blocks,
        fill(0, length(blocks)),
        old_cache.generation + 1,
    )

    assigned_blocks = falses(length(blocks))
    assigned_records = Set{Int}()

    for (id, record) in old_records
        record.valid || continue
        best_score = typemin(Int)
        best_index = 0
        tied = false

        for (index, block) in pairs(blocks)
            assigned_blocks[index] && continue
            block.kind == :eof && record.span.lo != record.span.hi && continue
            score = reindex_match_score(record.text, record.lines, block, info.text)

            if score > best_score
                best_score = score
                best_index = index
                tied = false
            elseif score == best_score
                tied = true
            end
        end

        if best_index != 0 && !tied && best_score > 0
            update_record_from_block!(record, key, best_index, blocks[best_index], info.text)
            record.path = path
            cache.handles[best_index] = id
            assigned_blocks[best_index] = true
            push!(assigned_records, id)
        else
            invalidate_record!(record)
        end
    end

    for (index, block) in pairs(blocks)
        assigned_blocks[index] && continue

        record = HandleRecord(
            key,
            path,
            index,
            block.span,
            block.lines,
            span_text(info.text, block.span),
            nothing,
            true,
        )
        handle = register_handle!(record)
        cache.handles[index] = handle.id
    end

    if old_cache.current_id !== nothing && old_cache.current_id != cache.current_id &&
        get(state.id_index, old_cache.current_id, nothing) == key
        delete!(state.id_index, old_cache.current_id)
    end

    state.files[key] = cache
    state.path_index[path] = key
    state.id_index[cache.current_id] = key
    return nothing
end

function reindex(path::AbstractString)
    abs_path = absolute_path(path)
    state = STATE[]

    if !haskey(state.path_index, abs_path)
        return nothing
    end

    key = state.path_index[abs_path]
    reindex_file!(key, abs_path)
    return nothing
end

function reindex()
    paths = String[]

    for cache in values(STATE[].files)
        isfile(cache.primary_path) && push!(paths, cache.primary_path)
    end

    for path in unique(paths)
        reindex(path)
    end

    return nothing
end
