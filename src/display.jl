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
Return the canonical cache path used when ordering a handle.
"""
function handle_primary_path(record::HandleRecord)
    if record.file !== nothing
        cache = get(STATE[].files, record.file, nothing)
        cache !== nothing && return cache.primary_path
    end

    return record.path
end

"""
Sort key used when displaying collections of handles.
"""
function handle_sort_key(handle::Handle)
    record = handle_record(handle)

    if record === nothing || !record.valid
        return ("\uffff", typemax(Int), typemax(Int), handle.id)
    end

    return (handle_primary_path(record), record.span.lo, record.span.hi, handle.id)
end

"""
Return a single-line preview of handle contents.
"""
function handle_preview(record::HandleRecord)
    preview = replace(strip(record.text), r"\n[ \t]*" => " ")
    ncodeunits(preview) > 40 && (preview = first(preview, 40) * "…")
    return preview
end

"""
Return line/span label column widths for overview entries.
"""
function handle_line_label_widths(records)
    start_width = 0
    stop_width = 0

    for record in records
        record.span.lo == record.span.hi && continue
        start_width = max(start_width, ndigits(record.lines.start))
        stop_width = max(stop_width, ndigits(record.lines.stop))
    end

    return (start_width, stop_width)
end

"""
Return a compact line/span label for an overview entry.
"""
function handle_line_label(record::HandleRecord, start_width::Integer=0, stop_width::Integer=0)
    if record.span.lo == record.span.hi
        return lpad("EOF", max(start_width, 3))
    end

    return "$(lpad(string(record.lines.start), start_width)) - $(lpad(string(record.lines.stop), stop_width))"
end

function Base.show(io::IO, ::MIME"text/plain", set::Set{Handle})
    ordered = sort(collect(set); by=handle_sort_key)
    count = length(ordered)
    print(io, "$count handle$(count == 1 ? "" : "s")")
    isempty(ordered) && return

    label_widths = Dict{String,Tuple{Int,Int}}()

    for handle in ordered
        record = handle_record(handle)
        (record === nothing || !record.valid) && continue
        primary_path = handle_primary_path(record)
        current_widths = get(label_widths, primary_path, (0, 0))
        record_widths = handle_line_label_widths((record,))
        label_widths[primary_path] = (
            max(current_widths[1], record_widths[1]),
            max(current_widths[2], record_widths[2]),
        )
    end

    current_primary_path = nothing

    for handle in ordered
        record = handle_record(handle)

        if record === nothing || !record.valid
            current_primary_path != "#invalid" && println(io, "\n#invalid:")
            current_primary_path = "#invalid"
            println(io, "  #invalid")
            continue
        end

        primary_path = handle_primary_path(record)

        if primary_path != current_primary_path
            println(io, "\n# $(record.path):")
            current_primary_path = primary_path
        end

        widths = get(label_widths, primary_path, (0, 0))
        println(io, "  $(handle_line_label(record, widths...)): $(handle_preview(record))")
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
            print(io, "$(handle_header(handle)) $(handle_preview(record))")
        end
    end
end
