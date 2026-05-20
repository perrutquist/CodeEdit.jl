"""
Return the index of the parsed block containing `offset`, or `nothing`.
"""
function block_index_for_offset(blocks::Vector{Block}, offset::Integer)
    for (index, block) in pairs(blocks)
        block.kind == :eof && continue
        block.span.lo <= offset < block.span.hi && return index
    end

    return nothing
end

"""
Collect module-boundary semicolon offsets grouped by the parsed block that
contains them.
"""
function collect_module_boundary_replacements!(
    replacements::Dict{Int,Vector{Int}},
    node,
    text::AbstractString,
    line_starts::Vector{Int},
    blocks::Vector{Block},
)
    if julia_kind(node, "module")
        for offset in unsafe_module_boundary_offsets(node, text, line_starts)
            block_index = block_index_for_offset(blocks, offset)
            block_index === nothing && continue
            push!(get!(replacements, block_index, Int[]), offset)
        end
    end

    for child in syntax_children(node)
        collect_module_boundary_replacements!(replacements, child, text, line_starts, blocks)
    end

    return replacements
end

"""
Return `text[span]` with selected semicolon byte offsets replaced by line breaks.
"""
function replace_offsets_with_linebreak(
    text::AbstractString,
    span::Span,
    offsets::Vector{Int},
    line_ending::AbstractString,
)
    relevant_offsets = sort(unique(offset for offset in offsets if span.lo <= offset < span.hi))
    isempty(relevant_offsets) && return span_text(text, span)

    io = IOBuffer()
    cursor = span.lo

    for offset in relevant_offsets
        if cursor < offset
            print(io, String(text[cursor:prevind(text, offset)]))
        end

        print(io, line_ending)
        cursor = nextind(text, offset)
    end

    if cursor < span.hi
        print(io, String(text[cursor:prevind(text, span.hi)]))
    end

    return String(take!(io))
end

"""
    format_modules(path)

Return an edit that puts unsafe multi-line module boundaries on their own lines.

The edit replaces semicolons with the file's existing line ending where a
multi-line module has body code on the same physical line as its `module`
declaration or closing `end`. The returned value is a `Replace` edit for one
affected block, or a `Combine` of `Replace` edits for multiple affected blocks.
"""
function format_modules(path::AbstractString)
    cache = load_file(path; parse_as=:julia)
    tree = julia_parse_tree(cache.text, cache.primary_path)

    replacements = Dict{Int,Vector{Int}}()
    collect_module_boundary_replacements!(
        replacements,
        tree,
        cache.text,
        cache.line_starts,
        cache.blocks,
    )

    edits = AbstractEdit[]

    for block_index in sort(collect(keys(replacements)))
        block = cache.blocks[block_index]
        replacement = replace_offsets_with_linebreak(
            cache.text,
            block.span,
            replacements[block_index],
            cache.line_ending,
        )

        replacement == span_text(cache.text, block.span) && continue
        push!(edits, Replace(block_handle(cache, block_index), replacement))
    end

    return Combine(edits...)
end
