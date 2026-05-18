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
Return whether a byte is Julia whitespace outside strings and comments.
"""
function is_julia_whitespace_byte(byte::UInt8)
    return byte in (UInt8('\t'), UInt8('\n'), UInt8('\v'), UInt8('\f'), UInt8('\r'), UInt8(' '))
end

"""
Return whether `bytes` starts with the ASCII string `needle` at byte offset `i`.
"""
function starts_with_ascii(bytes, i::Integer, needle::AbstractString)
    pattern = codeunits(needle)
    i + length(pattern) - 1 <= length(bytes) || return false

    for offset in eachindex(pattern)
        bytes[i + offset - 1] == pattern[offset] || return false
    end

    return true
end

"""
Copy byte range `first:last` to `io`.
"""
function write_byte_range!(io::IO, bytes, first::Integer, last::Integer)
    for i in first:last
        write(io, bytes[i])
    end

    return io
end

"""
Return a comment marker with indentation normalized away.
"""
function normalized_comment_marker(comment::AbstractString)
    normalized_newlines = replace(String(comment), "\r\n" => "\n", "\r" => "\n")
    lines = split(normalized_newlines, '\n'; keepempty=true)
    return "COMMENT(" * join(lstrip.(lines), "\n") * ")"
end

"""
Return the final byte offset of a quoted Julia literal starting at `i`.
"""
function quoted_literal_end(bytes, i::Integer)
    quotemark = bytes[i]

    if quotemark == UInt8('"') && starts_with_ascii(bytes, i, "\"\"\"")
        j = i + 3

        while j <= length(bytes) - 2
            starts_with_ascii(bytes, j, "\"\"\"") && return j + 2
            j += 1
        end

        return length(bytes)
    end

    escaped = false
    j = i + 1

    while j <= length(bytes)
        byte = bytes[j]

        if escaped
            escaped = false
        elseif byte == UInt8('\\')
            escaped = true
        elseif byte == quotemark
            return j
        end

        j += 1
    end

    return length(bytes)
end

"""
Return the final byte offset of a nested Julia block comment starting at `i`.
"""
function block_comment_end(bytes, i::Integer)
    depth = 1
    j = i + 2

    while j <= length(bytes) - 1
        if starts_with_ascii(bytes, j, "#=")
            depth += 1
            j += 2
        elseif starts_with_ascii(bytes, j, "=#")
            depth -= 1
            j += 2
            depth == 0 && return j - 1
        else
            j += 1
        end
    end

    return length(bytes)
end

"""
Return a source fingerprint that ignores formatting whitespace outside literals
and includes comments after normalizing comment indentation.
"""
function normalized_julia_source_fingerprint(text::AbstractString)
    bytes = codeunits(String(text))
    output = IOBuffer()
    i = 1

    while i <= length(bytes)
        byte = bytes[i]

        if is_julia_whitespace_byte(byte)
            i += 1
        elseif byte == UInt8('#')
            if i < length(bytes) && bytes[i + 1] == UInt8('=')
                stop = block_comment_end(bytes, i)
                write(output, normalized_comment_marker(String(bytes[i:stop])))
                i = stop + 1
            else
                stop = i

                while stop <= length(bytes) && bytes[stop] != UInt8('\n') && bytes[stop] != UInt8('\r')
                    stop += 1
                end

                write(output, normalized_comment_marker(String(bytes[i:(stop - 1)])))
                i = stop
            end
        elseif byte == UInt8('"') || byte == UInt8('\'')
            stop = quoted_literal_end(bytes, i)
            write_byte_range!(output, bytes, i, stop)
            i = stop + 1
        else
            write(output, byte)
            i += 1
        end
    end

    return String(take!(output))
end

"""
Return the block kind recorded for `record` in `cache`, or `nothing`.
"""
function cached_record_kind(cache::FileCache, record::HandleRecord)
    record.block_index in eachindex(cache.blocks) || return nothing
    return cache.blocks[record.block_index].kind
end

"""
Return a formatter-stable syntax fingerprint for a Julia block.

Most Julia blocks are independently parsed before fingerprinting. Module header
and footer blocks are special because they are fragments of a larger module
definition. Module footer comments are deliberately ignored so changing
`end # module Foo` to `end` does not invalidate the handle.
"""
function syntax_reindex_fingerprint(
    text::AbstractString,
    kind::Union{Nothing,Symbol},
    parse_as::Symbol;
    path::AbstractString="<memory>",
)
    @show text kind
    parse_as == :julia || return nothing
    kind === nothing && return nothing
    kind == :eof && return "julia:eof"
    kind == :module_footer && return "julia:module_footer:end"

    if kind == :julia
        try
            validate_julia_parse(text, path)
        catch
            return nothing
        end
    end

    return "julia:$kind:" * normalized_julia_source_fingerprint(text)
end

"""
Assign an existing handle record to a newly parsed block.
"""
function assign_reindex_match!(
    cache::FileCache,
    record::HandleRecord,
    id::Integer,
    index::Integer,
    key::FileKey,
    blocks::Vector{Block},
    text::AbstractString,
    path::AbstractString,
    assigned_blocks::AbstractVector{Bool},
    assigned_records::Set{Int},
)
    update_record_from_block!(record, key, index, blocks[index], text)
    record.path = String(path)
    cache.handles[index] = id
    assigned_blocks[index] = true
    push!(assigned_records, id)
    return nothing
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
    matched_block_for_record = Dict{Int,Int}()
    old_record_ids = [id for id in old_cache.handles if haskey(old_records, id)]
    old_positions = Dict(id => index for (index, id) in pairs(old_record_ids))
    old_fingerprints = Dict{Int,String}()

    for id in old_record_ids
        record = old_records[id]
        record.valid || continue

        fingerprint = syntax_reindex_fingerprint(
            record.text,
            cached_record_kind(old_cache, record),
            old_cache.parse_as;
            path=record.path,
        )

        fingerprint === nothing && continue
        old_fingerprints[id] = fingerprint
    end

    new_fingerprints = Union{Nothing,String}[
        syntax_reindex_fingerprint(span_text(info.text, block.span), block.kind, old_cache.parse_as; path=path)
        for block in blocks
    ]

    for id in old_record_ids
        record = old_records[id]
        record.valid || continue
        fingerprint = get(old_fingerprints, id, nothing)
        fingerprint === nothing && continue

        candidates = [
            index for (index, candidate_fingerprint) in pairs(new_fingerprints) if
            !assigned_blocks[index] && candidate_fingerprint == fingerprint
        ]

        if length(candidates) == 1
            index = only(candidates)
            assign_reindex_match!(
                cache,
                record,
                id,
                index,
                key,
                blocks,
                info.text,
                path,
                assigned_blocks,
                assigned_records,
            )
            matched_block_for_record[id] = index
        elseif length(candidates) > 1
            anchored_index = 0
            position = old_positions[id]

            if position == 1
                anchored_index = 1 in candidates ? 1 : 0
            else
                previous_id = old_record_ids[position - 1]
                previous_index = get(matched_block_for_record, previous_id, 0)
                candidate_index = previous_index + 1
                anchored_index = candidate_index in candidates ? candidate_index : 0
            end

            if anchored_index != 0
                assign_reindex_match!(
                    cache,
                    record,
                    id,
                    anchored_index,
                    key,
                    blocks,
                    info.text,
                    path,
                    assigned_blocks,
                    assigned_records,
                )
                matched_block_for_record[id] = anchored_index
            else
                invalidate_record!(record)
                push!(assigned_records, id)
            end
        end
    end

    for id in old_record_ids
        id in assigned_records && continue
        record = old_records[id]
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
            assign_reindex_match!(
                cache,
                record,
                id,
                best_index,
                key,
                blocks,
                info.text,
                path,
                assigned_blocks,
                assigned_records,
            )
        else
            invalidate_record!(record)
            push!(assigned_records, id)
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
