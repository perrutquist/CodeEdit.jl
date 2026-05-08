"""
Return a zero-width span at the end of `text`.
"""
eof_span(text::AbstractString) = Span(ncodeunits(text) + 1, ncodeunits(text) + 1)

"""
Return the public EOF line number for `text`.
"""
eof_line(text::AbstractString, line_starts::Vector{Int}) = line_count(line_starts) + 1

"""
Validate that `span` is a well-formed half-open byte span into `text`.
"""
function validate_span(text::AbstractString, span::Span)
    limit = ncodeunits(text) + 1
    1 <= span.lo <= span.hi <= limit || throw(ArgumentError("invalid span: $span"))
    is_byte_boundary(text, span.lo) || throw(ArgumentError("span starts inside a character: $span"))
    is_byte_boundary(text, span.hi) || throw(ArgumentError("span ends inside a character: $span"))
    return span
end

"""
Return whether `offset` is a valid string byte boundary or EOF.
"""
function is_byte_boundary(text::AbstractString, offset::Integer)
    return offset == ncodeunits(text) + 1 || (1 <= offset <= ncodeunits(text) && isvalid(text, offset))
end

"""
Slice `text` by a half-open byte span.
"""
function span_text(text::AbstractString, span::Span)
    validate_span(text, span)
    span.lo == span.hi && return ""
    return String(text[span.lo:prevind(text, span.hi)])
end

"""
Build byte offsets for the first byte of each physical line.

The vector is empty for an empty file. A final empty line after a trailing
newline is represented by EOF rather than by an additional line start.
"""
function build_line_starts(text::AbstractString)
    isempty(text) && return Int[]

    starts = Int[1]
    limit = ncodeunits(text)

    for i in eachindex(text)
        if text[i] == '\n'
            next = nextind(text, i)
            next <= limit && push!(starts, next)
        end
    end

    return starts
end

line_count(line_starts::Vector{Int}) = length(line_starts)

"""
Return the full byte span for a line, including its line ending when present.
"""
function line_span(text::AbstractString, line_starts::Vector{Int}, line::Integer)
    1 <= line <= length(line_starts) || throw(ArgumentError("line is outside file bounds: $line"))

    lo = line_starts[line]
    hi = line == length(line_starts) ? ncodeunits(text) + 1 : line_starts[line + 1]
    return Span(lo, hi)
end

"""
Return the byte span for a line's content, excluding CRLF/LF line endings.
"""
function line_content_span(text::AbstractString, line_starts::Vector{Int}, line::Integer)
    full = line_span(text, line_starts, line)
    hi = full.hi

    if hi > full.lo && codeunit(text, hi - 1) == UInt8('\n')
        hi -= 1
        if hi > full.lo && codeunit(text, hi - 1) == UInt8('\r')
            hi -= 1
        end
    end

    return Span(full.lo, hi)
end

"""
Return the number of characters in a line, excluding its line ending.
"""
function line_char_count(text::AbstractString, line_starts::Vector{Int}, line::Integer)
    return length(span_text(text, line_content_span(text, line_starts, line)))
end

"""
Convert a public `(line, pos)` character position to a byte offset.

`pos` is a one-based character position within the line content. The position
one past the last character is accepted and returns the end of line content.
"""
function byte_offset_for_line_pos(text::AbstractString, line_starts::Vector{Int}, line::Integer, pos::Integer)
    content = line_content_span(text, line_starts, line)
    char_count = line_char_count(text, line_starts, line)
    1 <= pos <= char_count + 1 || throw(ArgumentError("character position is outside line bounds: $pos"))

    offset = content.lo
    for _ in 1:(pos - 1)
        offset = nextind(text, offset)
    end

    return offset
end

"""
Return the line range touched by `span`.
"""
function line_range_for_span(text::AbstractString, line_starts::Vector{Int}, span::Span)
    validate_span(text, span)

    if span.lo == span.hi == ncodeunits(text) + 1
        line = eof_line(text, line_starts)
        return line:line
    end

    isempty(line_starts) && return 1:1

    start_line = max(1, searchsortedlast(line_starts, span.lo))
    end_byte = max(span.lo, span.hi - 1)
    end_line = max(start_line, searchsortedlast(line_starts, end_byte))

    return start_line:end_line
end
