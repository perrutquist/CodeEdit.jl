"""
Parse Julia source with JuliaSyntax without throwing on syntax errors.
"""
function julia_parse_green_tree(text::AbstractString, path::AbstractString="<memory>")
    return JuliaSyntax.parseall(
        JuliaSyntax.GreenNode,
        text;
        filename=String(path),
        raise=false,
    )
end

"""
Collect JuliaSyntax error-node messages from a GreenNode tree.
"""
function collect_julia_parse_errors!(
    errors::Vector{String},
    node,
    offset::Integer=0,
)
    if JuliaSyntax.kind(node) == JuliaSyntax.K"error"
        push!(errors, "Julia syntax error at byte offset $offset: $node")
    end

    child_offset = offset

    for child in syntax_children(node)
        collect_julia_parse_errors!(errors, child, child_offset)
        child_offset += Int(JuliaSyntax.span(child))
    end

    return errors
end

"""
Return Julia syntax validation errors without throwing.
"""
function julia_parse_errors(text::AbstractString, path::AbstractString="<memory>")
    tree = julia_parse_green_tree(text, path)
    errors = String[]
    collect_julia_parse_errors!(errors, tree)
    return errors
end

"""
Parse Julia source with JuliaSyntax.
"""
function julia_parse_tree(text::AbstractString, path::AbstractString="<memory>")
    errors = julia_parse_errors(text, path)

    if !isempty(errors)
        throw(ArgumentError(join(errors, "\n")))
    end

    return JuliaSyntax.parseall(
        JuliaSyntax.SyntaxNode,
        text;
        filename=String(path),
        ignore_trivia=true,
        ignore_warnings=true,
    )
end

"""
Validate Julia source using JuliaSyntax.
"""
function validate_julia_parse(text::AbstractString, path::AbstractString="<memory>")
    errors = julia_parse_errors(text, path)
    isempty(errors) && return nothing
    throw(ArgumentError(join(errors, "\n")))
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


const _unsafe_module_boundary_warning_paths = Set{String}()

"""
Warn once for a file when a multi-line module cannot be safely split into
line-oriented header/body/footer blocks.
"""
function warn_unsafe_module_boundaries_once(path::AbstractString)
    path_string = String(path)
    path_string in _unsafe_module_boundary_warning_paths && return nothing

    push!(_unsafe_module_boundary_warning_paths, path_string)
    @warn(
        "CodeEdit cannot safely split a multi-line module because its header or closing end shares a line with body code. Put the module declaration and closing end on their own lines, or run `format_modules($(repr(path_string)))` and apply the returned edit.",
        path = path_string,
    )
    return nothing
end

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
Return whether any physical line in `lines` is a Julia line comment.
"""
function contains_julia_comment_line(text::AbstractString, line_starts::Vector{Int}, lines)
    for line in lines
        is_julia_comment_line(text, line_starts, line) && return true
    end

    return false
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
Push a trailing comment block for a parsed Julia region and return the next
cursor line.

JuliaSyntax ignores comments as trivia. Leading comments are attached to the
following syntax node, but final comments have no following node and need their
own block to preserve source reconstruction.
"""
function push_julia_trailing_comment_block!(
    blocks::Vector{Block},
    text::AbstractString,
    line_starts::Vector{Int},
    cursor_line::Integer,
    end_line::Integer,
)
    cursor_line <= end_line || return cursor_line
    contains_julia_comment_line(text, line_starts, cursor_line:end_line) || return cursor_line

    push_julia_line_block!(blocks, text, line_starts, cursor_line, end_line, :comment)
    return end_line + 1
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
Return the first semicolon byte offset in `span`, optionally before `before`.
"""
function first_semicolon_offset(text::AbstractString, span::Span; before::Integer=span.hi)
    hi = min(span.hi - 1, before - 1)
    hi < span.lo && return nothing

    for offset in span.lo:hi
        codeunit(text, offset) == UInt8(';') && return offset
    end

    return nothing
end

"""
Return the last semicolon byte offset in `span`, optionally after `after` and
before `before`.
"""
function last_semicolon_offset(
    text::AbstractString,
    span::Span;
    after::Integer=span.lo,
    before::Integer=span.hi - 1,
)
    lo = max(span.lo, after)
    hi = min(span.hi - 1, before)
    hi < lo && return nothing

    for offset in hi:-1:lo
        codeunit(text, offset) == UInt8(';') && return offset
    end

    return nothing
end

"""
Return byte offsets of module-boundary semicolons that should become line breaks.

Only multi-line modules are considered. A header boundary is unsafe when body
syntax starts on the module declaration line. A footer boundary is unsafe when
body syntax ends on the module closing line.
"""
function unsafe_module_boundary_offsets(node, text::AbstractString, line_starts::Vector{Int})
    module_lines = syntax_node_line_range(node, line_starts)
    first_line = module_lines.start
    last_line = module_lines.stop
    last_line <= first_line && return Int[]

    body = module_body_node(node)
    body === nothing && return Int[]

    header_body_start = typemax(Int)
    footer_body_end = 0

    for child in syntax_children(body)
        child_lines = syntax_node_line_range(child, line_starts)

        if child_lines.start == first_line
            header_body_start = min(header_body_start, Int(JuliaSyntax.first_byte(child)))
        end

        if child_lines.stop == last_line
            footer_body_end = max(footer_body_end, Int(JuliaSyntax.last_byte(child)))
        end
    end

    offsets = Int[]

    if header_body_start != typemax(Int)
        header_line = line_content_span(text, line_starts, first_line)
        offset = first_semicolon_offset(text, header_line; before=header_body_start)
        offset === nothing && (offset = first_semicolon_offset(text, header_line))
        offset === nothing || push!(offsets, offset)
    end

    if footer_body_end != 0
        footer_line = line_content_span(text, line_starts, last_line)
        offset = last_semicolon_offset(
            text,
            footer_line;
            after=footer_body_end + 1,
            before=Int(JuliaSyntax.last_byte(node)),
        )
        offset === nothing && (offset = last_semicolon_offset(text, footer_line))
        offset === nothing || push!(offsets, offset)
    end

    return unique(offsets)
end

"""
Return whether a multi-line module has body code on a boundary line.
"""
function has_unsafe_module_boundaries(node, line_starts::Vector{Int})
    module_lines = syntax_node_line_range(node, line_starts)
    module_lines.stop <= module_lines.start && return false

    body = module_body_node(node)
    body === nothing && return false

    for child in syntax_children(body)
        child_lines = syntax_node_line_range(child, line_starts)
        (child_lines.start == module_lines.start || child_lines.stop == module_lines.stop) && return true
    end

    return false
end

"""
Push Julia blocks for `node` and return the next cursor line.
"""
function push_julia_node_blocks!(
    blocks::Vector{Block},
    node,
    text::AbstractString,
    line_starts::Vector{Int},
    cursor_line::Integer;
    path::AbstractString="<memory>",
)
    if julia_kind(node, "module")
        return push_julia_module_blocks!(blocks, node, text, line_starts, cursor_line; path=path)
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
    cursor_line::Integer;
    path::AbstractString="<memory>",
)
    module_lines = syntax_node_line_range(node, line_starts)
    first_line = module_lines.start
    last_line = module_lines.stop

    if last_line <= first_line
        return push_julia_syntax_block!(blocks, node, text, line_starts, cursor_line)
    end

    if has_unsafe_module_boundaries(node, line_starts)
        warn_unsafe_module_boundaries_once(path)
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

            body_cursor = push_julia_node_blocks!(blocks, child, text, line_starts, body_cursor; path=path)
        end
    end

    push_julia_trailing_comment_block!(blocks, text, line_starts, body_cursor, last_line - 1)

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

        cursor_line = push_julia_node_blocks!(blocks, node, text, line_starts, cursor_line; path=path)
    end

    push_julia_trailing_comment_block!(
        blocks,
        text,
        line_starts,
        cursor_line,
        line_count(line_starts),
    )

    eof = eof_span(text)
    eof_lineno = eof_line(text, line_starts)
    push!(blocks, Block(eof, eof_lineno:eof_lineno, :eof))

    return blocks
end
