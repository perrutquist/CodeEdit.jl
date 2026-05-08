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

const JULIA_BLOCK_OPENING_KEYWORDS = (
    "baremodule",
    "begin",
    "do",
    "for",
    "function",
    "if",
    "let",
    "macro",
    "module",
    "quote",
    "struct",
    "try",
    "while",
)

"""
Return `line` with any trailing Julia line comment removed.

This helper is intentionally conservative and only supports enough lexical
state to keep block-boundary heuristics from treating comments as code.
JuliaSyntax still validates the whole source before block detection runs.
"""
function strip_julia_line_comment(line::AbstractString)
    in_string = false
    quote_char = '\0'
    escaped = false

    for i in eachindex(line)
        char = line[i]

        if in_string
            if escaped
                escaped = false
            elseif char == '\\'
                escaped = true
            elseif char == quote_char
                in_string = false
            end
        elseif char == '"' || char == '\''
            in_string = true
            quote_char = char
        elseif char == '#'
            return i == firstindex(line) ? "" : String(line[firstindex(line):prevind(line, i)])
        end
    end

    return String(line)
end

"""
Return the stripped source used for Julia block-boundary heuristics.
"""
function julia_boundary_source(text::AbstractString, line_starts::Vector{Int}, line::Integer)
    source = span_text(text, line_content_span(text, line_starts, line))
    return strip(strip_julia_line_comment(source))
end

"""
Return the number of word-boundary occurrences of a Julia keyword in `source`.
"""
function julia_keyword_count(source::AbstractString, keyword::AbstractString)
    return length(collect(eachmatch(Regex("\\b$(keyword)\\b"), source)))
end

"""
Return the block-nesting delta implied by a single physical source line.
"""
function julia_line_nesting_delta(source::AbstractString)
    isempty(source) && return 0

    openings = sum(keyword -> julia_keyword_count(source, keyword), JULIA_BLOCK_OPENING_KEYWORDS)
    closings = julia_keyword_count(source, "end")
    return openings - closings
end

"""
Return the final line of the top-level Julia block starting at `code_line`.
"""
function julia_block_end_line(text::AbstractString, line_starts::Vector{Int}, code_line::Integer)
    line_total = line_count(line_starts)
    nesting = 0

    for line in code_line:line_total
        source = julia_boundary_source(text, line_starts, line)
        nesting += julia_line_nesting_delta(source)

        nesting <= 0 && return line
    end

    return line_total
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

        end_line = julia_block_end_line(text, line_starts, code_line)

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
