"""
Return a compact source-location header for a handle.
"""
function handle_header(handle::Handle)
    record = handle_record(handle)

    if record === nothing || !record.valid
        return "#invalid"
    end

    block_label = record.span.lo == record.span.hi ? "EOF" : "$(record.lines.start) - $(record.lines.stop)"
    return "# $(record.path) $block_label:"
end

"""
Write a full handle display to `io`.
"""
function show_handle(io::IO, handle::Handle)
    record = handle_record(handle)

    if record === nothing || !record.valid
        print(io, "#invalid")
        return
    end

    println(io, handle_header(handle))
    print(io, record.text)
    return
end

function Base.show(io::IO, ::MIME"text/plain", handle::Handle)
    show_handle(io, handle)
end

function Base.show(io::IO, handle::Handle)
    show_handle(io, handle)
end

"""
Sort key used when displaying sets of handles.
"""
function handle_sort_key(handle::Handle)
    record = handle_record(handle)

    if record === nothing || !record.valid
        return ("\uffff", typemax(Int), typemax(Int), handle.id)
    end

    return (record.path, record.lines.start, record.lines.stop, handle.id)
end

function Base.show(io::IO, ::MIME"text/plain", set::Set{Handle})
    ordered = sort(collect(set); by=handle_sort_key)

    for (index, handle) in pairs(ordered)
        index > 1 && println(io)
        show_handle(io, handle)
    end
end

function Base.show(io::IO, ::MIME"text/plain", vector::Vector{Handle})
    if length(vector) == 1
        show_handle(io, only(vector))
        return
    end

    for (index, handle) in pairs(sort(collect(vector); by=handle_sort_key))
        record = handle_record(handle)
        index > 1 && println(io)

        if record === nothing || !record.valid
            print(io, "#invalid")
        else
            preview = replace(strip(record.text), '\n' => ' ')
            ncodeunits(preview) > 40 && (preview = first(preview, 40) * "…")
            print(io, "$(handle_header(handle)) $preview")
        end
    end
end
