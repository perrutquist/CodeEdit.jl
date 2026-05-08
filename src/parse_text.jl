"""
Return whether a line is blank after removing its line ending.
"""
function is_blank_line(text::AbstractString, line_starts::Vector{Int}, line::Integer)
    content = span_text(text, line_content_span(text, line_starts, line))
    return all(isspace, content)
end

"""
Parse non-Julia text into paragraph-like blocks separated by blank lines.

The returned blocks include an EOF block.
"""
function parse_text_blocks(text::AbstractString, line_starts::Vector{Int}=build_line_starts(text))
    blocks = Block[]
    line_total = line_count(line_starts)
    line = 1

    while line <= line_total
        if is_blank_line(text, line_starts, line)
            line += 1
            continue
        end

        start_line = line
        while line <= line_total && !is_blank_line(text, line_starts, line)
            line += 1
        end
        end_line = line - 1

        lo = line_span(text, line_starts, start_line).lo
        hi = line_span(text, line_starts, end_line).hi
        push!(blocks, Block(Span(lo, hi), start_line:end_line, :text))
    end

    eof = eof_span(text)
    eof_lineno = eof_line(text, line_starts)
    push!(blocks, Block(eof, eof_lineno:eof_lineno, :eof))

    return blocks
end
