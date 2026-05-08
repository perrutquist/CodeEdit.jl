"""
Parse Julia source with JuliaSyntax and normalize parse errors.
"""
function julia_parse_tree(text::AbstractString, path::AbstractString="<memory>")
    try
        return JuliaSyntax.parseall(
            JuliaSyntax.SyntaxNode,
            text;
            filename=String(path),
            ignore_trivia=true,
            ignore_warnings=false,
        )
    catch
        throw(ArgumentError("Julia file could not be parsed: $path"))
    end
end

"""
Validate Julia source using JuliaSyntax.
"""
function validate_julia_parse(text::AbstractString, path::AbstractString="<memory>")
    julia_parse_tree(text, path)
    return nothing
end

"""
Return the iterable children of a JuliaSyntax node.
"""
function syntax_children(node)
    children = JuliaSyntax.children(node)
    return children === nothing ? () : children
end

"""
Return whether a JuliaSyntax node has kind `name`.
"""
julia_kind(node, name::AbstractString) = JuliaSyntax.kind(node) == JuliaSyntax.Kind(name)

"""
Return the physical source-line range covered by a JuliaSyntax node.
"""
function syntax_node_line_range(node, line_starts::Vector{Int})
    line_total = line_count(line_starts)
    line_total == 0 && return 1:1

    first_line = clamp(Int(JuliaSyntax.source_line(node)), 1, line_total)
    last_line = clamp(
        Int(JuliaSyntax.source_line(JuliaSyntax.sourcefile(node), JuliaSyntax.last_byte(node))),
        first_line,
        line_total,
    )

    return first_line:last_line
end

"""
Return whether a physical line is a Julia line comment.
"""
function is_julia_comment_line(text::AbstractString, line_starts::Vector{Int}, line::Integer)
    content = strip(span_text(text, line_content_span(text, line_starts, line)))
    return startswith(content, "#")
end

"""
Return the first line to include with a syntax node after attaching adjacent
leading comment lines.
"""
function attached_leading_start_line(
    text::AbstractString,
    line_starts::Vector{Int},
    cursor_line::Integer,
    syntax_start_line::Integer,
)
    start_line = syntax_start_line
    candidate = syntax_start_line - 1

    while candidate >= cursor_line
        is_julia_comment_line(text, line_starts, candidate) || break
        start_line = candidate
        candidate -= 1
    end

    return start_line
end

"""
Push a non-overlapping line-oriented Julia block.

When JuliaSyntax identifies multiple top-level statements on the same physical
line, line-oriented block spans would overlap. Merge those cases conservatively
rather than returning overlapping blocks.
"""
function push_julia_line_block!(
    blocks::Vector{Block},
    text::AbstractString,
    line_starts::Vector{Int},
    start_line::Integer,
    end_line::Integer,
    kind::Symbol,
)
    start_line <= end_line || return blocks

    if !isempty(blocks) && blocks[end].kind != :eof && start_line <= blocks[end].lines.stop
        previous = blocks[end]
        merged_lines = previous.lines.start:max(previous.lines.stop, end_line)
        merged_hi = line_span(text, line_starts, merged_lines.stop).hi
        merged_kind = previous.kind == kind ? kind : :julia
        blocks[end] = Block(Span(previous.span.lo, merged_hi), merged_lines, merged_kind)
        return blocks
    end

    lo = line_span(text, line_starts, start_line).lo
    hi = line_span(text, line_starts, end_line).hi
    push!(blocks, Block(Span(lo, hi), start_line:end_line, kind))
    return blocks
end

"""
Push a normal Julia syntax node as one block and return the next cursor line.
"""
function push_julia_syntax_block!(
    blocks::Vector{Block},
    node,
    text::AbstractString,
    line_starts::Vector{Int},
    cursor_line::Integer;
    kind::Symbol=:julia,
)
    node_lines = syntax_node_line_range(node, line_starts)
    start_line = attached_leading_start_line(text, line_starts, cursor_line, node_lines.start)
    push_julia_line_block!(blocks, text, line_starts, start_line, node_lines.stop, kind)
    return node_lines.stop + 1
end

"""
Return the body block child of a JuliaSyntax module node, if it is clear.
"""
function module_body_node(node)
    for child in syntax_children(node)
        julia_kind(child, "block") && return child
    end

    return nothing
end

"""
Push Julia blocks for `node` and return the next cursor line.
"""
function push_julia_node_blocks!(
    blocks::Vector{Block},
    node,
    text::AbstractString,
    line_starts::Vector{Int},
    cursor_line::Integer,
)
    if julia_kind(node, "module")
        return push_julia_module_blocks!(blocks, node, text, line_starts, cursor_line)
    end

    return push_julia_syntax_block!(blocks, node, text, line_starts, cursor_line)
end

"""
Push a module as header, recursively parsed body blocks, and footer.

If the module is not clearly multi-line, keep it as a single conservative
block rather than inventing overlapping header/footer/body spans.
"""
function push_julia_module_blocks!(
    blocks::Vector{Block},
    node,
    text::AbstractString,
    line_starts::Vector{Int},
    cursor_line::Integer,
)
    module_lines = syntax_node_line_range(node, line_starts)
    first_line = module_lines.start
    last_line = module_lines.stop

    if last_line <= first_line
        return push_julia_syntax_block!(blocks, node, text, line_starts, cursor_line)
    end

    header_start = attached_leading_start_line(text, line_starts, cursor_line, first_line)
    push_julia_line_block!(blocks, text, line_starts, header_start, first_line, :module_header)

    body = module_body_node(node)
    body_cursor = first_line + 1

    if body !== nothing
        for child in syntax_children(body)
            child_lines = syntax_node_line_range(child, line_starts)
            child_lines.start <= first_line && continue
            child_lines.stop >= last_line && continue

            body_cursor = push_julia_node_blocks!(blocks, child, text, line_starts, body_cursor)
        end
    end

    push_julia_line_block!(blocks, text, line_starts, last_line, last_line, :module_footer)
    return last_line + 1
end

"""
Parse Julia text into top-level blocks using JuliaSyntax source ranges.

JuliaSyntax is responsible for parsing, validation, source ordering, docstring
nodes, and expression extents. This layer only maps syntax nodes to CodeEdit's
line-oriented block model, attaches immediately adjacent leading line comments,
splits clear multi-line modules into header/body/footer blocks, and appends EOF.
"""
function parse_julia_blocks(
    text::AbstractString,
    line_starts::Vector{Int}=build_line_starts(text);
    path::AbstractString="<memory>",
)
    tree = julia_parse_tree(text, path)

    blocks = Block[]
    cursor_line = 1

    for node in syntax_children(tree)
        node_lines = syntax_node_line_range(node, line_starts)
        node_lines.stop < cursor_line && continue

        cursor_line = push_julia_node_blocks!(blocks, node, text, line_starts, cursor_line)
    end

    eof = eof_span(text)
    eof_lineno = eof_line(text, line_starts)
    push!(blocks, Block(eof, eof_lineno:eof_lineno, :eof))

    return blocks
end
