"""
Validate Julia source using JuliaSyntax.

This intentionally keeps validation separate from block boundary detection so
the initial parser can remain conservative and easy to test.
"""
function validate_julia_parse(text::AbstractString, path::AbstractString="<memory>")
    try
        JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, text; ignore_warnings=false)
    catch err
        throw(ArgumentError("Julia file could not be parsed: $path"))
    end

    return nothing
end

"""
Return whether a physical line is a Julia line comment.
"""
function is_julia_comment_line(text::AbstractString, line_starts::Vector{Int}, line::Integer)
    content = strip(span_text(text, line_content_span(text, line_starts, line)))
    return startswith(content, "#")
end

"""
Return the first nonblank, non-comment line at or after `line`.
"""
function next_julia_code_line(text::AbstractString, line_starts::Vector{Int}, line::Integer)
    line_total = line_count(line_starts)

    while line <= line_total
        if is_blank_line(text, line_starts, line) || is_julia_comment_line(text, line_starts, line)
            line += 1
            continue
        end

        return line
    end

    return line_total + 1
end

"""
Parse Julia text into conservative top-level blocks.

This implementation validates the whole file with JuliaSyntax, then uses
Julia's parser to identify top-level expression extents. Immediately adjacent
leading comment lines are attached to the following expression. EOF is always
appended as its own block.
"""
function parse_julia_blocks(
    text::AbstractString,
    line_starts::Vector{Int}=build_line_starts(text);
    path::AbstractString="<memory>",
)
    validate_julia_parse(text, path)

    blocks = Block[]
    line_total = line_count(line_starts)
    line = 1

    while line <= line_total
        while line <= line_total && is_blank_line(text, line_starts, line)
            line += 1
        end
        line > line_total && break

        start_line = line
        code_line = next_julia_code_line(text, line_starts, line)
        code_line > line_total && break

        expr_start = line_span(text, line_starts, code_line).lo
        expr, next_index = Meta.parse(String(text), expr_start; greedy=false, raise=true)
        expr === nothing && throw(ArgumentError("Julia file could not be parsed: $path"))

        expr_span = Span(expr_start, min(next_index, ncodeunits(text) + 1))
        expr_lines = line_range_for_span(text, line_starts, expr_span)
        end_line = expr_lines.stop

        block_lo = line_span(text, line_starts, start_line).lo
        block_hi = line_span(text, line_starts, end_line).hi
        push!(blocks, Block(Span(block_lo, block_hi), start_line:end_line, :julia))

        line = end_line + 1
    end

    eof = eof_span(text)
    eof_lineno = eof_line(text, line_starts)
    push!(blocks, Block(eof, eof_lineno:eof_lineno, :eof))

    return blocks
end
