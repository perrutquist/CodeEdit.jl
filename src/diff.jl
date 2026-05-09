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
Return a classic diff range for a possibly empty line span.
"""
function diff_range(start::Integer, stop::Integer)
    stop < start && return string(start - 1)
    start == stop && return string(start)
    return "$start,$stop"
end

"""
Return a compact deterministic classic-style diff.
"""
function classic_diff(old::AbstractString, new::AbstractString)
    old == new && return "No changes.\n"

    old_lines = diff_lines(old)
    new_lines = diff_lines(new)
    shared_prefix = 0
    shared_limit = min(length(old_lines), length(new_lines))

    while shared_prefix < shared_limit && old_lines[shared_prefix + 1] == new_lines[shared_prefix + 1]
        shared_prefix += 1
    end

    shared_suffix = 0
    suffix_limit = shared_limit - shared_prefix

    while shared_suffix < suffix_limit &&
        old_lines[end - shared_suffix] == new_lines[end - shared_suffix]
        shared_suffix += 1
    end

    old_start = shared_prefix + 1
    old_stop = length(old_lines) - shared_suffix
    new_start = shared_prefix + 1
    new_stop = length(new_lines) - shared_suffix
    old_changed = old_start <= old_stop ? old_lines[old_start:old_stop] : String[]
    new_changed = new_start <= new_stop ? new_lines[new_start:new_stop] : String[]

    io = IOBuffer()
    println(io, "$(diff_range(old_start, old_stop))c$(diff_range(new_start, new_stop))")

    for line in old_changed
        print(io, "< ")
        print(io, line)
        endswith(line, "\n") || println(io)
    end

    println(io, "---")

    for line in new_changed
        print(io, "> ")
        print(io, line)
        endswith(line, "\n") || println(io)
    end

    return String(take!(io))
end
