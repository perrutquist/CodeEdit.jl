"""
Return source text split into physical lines while preserving line endings.
"""
function diff_lines(text::AbstractString)
    lines = String[]
    start = firstindex(text)

    while start <= ncodeunits(text)
        newline = findnext('\n', text, start)

        if newline === nothing
            push!(lines, String(text[start:end]))
            break
        end

        push!(lines, String(text[start:newline]))
        start = nextind(text, newline)
    end

    return lines
end

"""
Return a compact deterministic classic-style whole-file diff.
"""
function classic_diff(old::AbstractString, new::AbstractString)
    old == new && return "No changes.\n"

    old_lines = diff_lines(old)
    new_lines = diff_lines(new)
    old_range = isempty(old_lines) ? "0" : length(old_lines) == 1 ? "1" : "1,$(length(old_lines))"
    new_range = isempty(new_lines) ? "0" : length(new_lines) == 1 ? "1" : "1,$(length(new_lines))"

    io = IOBuffer()
    println(io, "$(old_range)c$(new_range)")

    for line in old_lines
        print(io, "< ")
        print(io, line)
        endswith(line, "\n") || println(io)
    end

    println(io, "---")

    for line in new_lines
        print(io, "> ")
        print(io, line)
        endswith(line, "\n") || println(io)
    end

    return String(take!(io))
end
