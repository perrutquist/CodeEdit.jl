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
Write version-control keyword arguments in constructor-call form.
"""
function show_version_control_kwargs(io::IO, kwargs::NamedTuple)
    isempty(keys(kwargs)) && return

    print(io, "; ")

    for (index, key) in enumerate(keys(kwargs))
        index > 1 && print(io, ", ")
        print(io, key, "=")
        show(io, getfield(kwargs, key))
    end
end

function Base.show(io::IO, vc::VersionControl{T}) where {T}
    if T === :git
        print(io, "GitVersionControl(")
        show(io, vc.repo_path)
        show_version_control_kwargs(io, vc.kwargs)
        print(io, ")")
    elseif T === :none
        print(io, "NoVersionControl(")
        show_version_control_kwargs(io, vc.kwargs)
        print(io, ")")
    else
        print(io, "VersionControl(")
        show(io, vc.repo_path)
        show_version_control_kwargs(io, vc.kwargs)
        print(io, ")")
    end
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
Return whether a byte is part of an ASCII word/symbol token.
"""
function is_ascii_word_codeunit(byte::UInt8)
    return UInt8('A') <= byte <= UInt8('Z') ||
        UInt8('a') <= byte <= UInt8('z') ||
        UInt8('0') <= byte <= UInt8('9') ||
        byte == UInt8('_')
end

"""
Return whether cutting after `cut_codeunits` would split an ASCII word/symbol token.
"""
function splits_ascii_word(preview::String, cut_codeunits::Integer)
    cut_codeunits <= 0 && return false
    cut_codeunits >= ncodeunits(preview) && return false

    return is_ascii_word_codeunit(codeunit(preview, cut_codeunits)) &&
        is_ascii_word_codeunit(codeunit(preview, cut_codeunits + 1))
end

"""
Return the preferred truncation point for a preview, measured in codeunits.
"""
function preview_truncation_codeunits(preview::String, limit::Integer=40, max_extra::Integer=20)
    total = ncodeunits(preview)
    total <= limit && return total

    max_cut = min(total, limit + max_extra)
    last_candidate = 0

    for index in eachindex(preview)
        cut_codeunits = nextind(preview, index) - 1
        cut_codeunits > max_cut && break
        last_candidate = cut_codeunits

        if cut_codeunits >= limit && !splits_ascii_word(preview, cut_codeunits)
            return cut_codeunits
        end
    end

    for index in reverse(collect(eachindex(preview)))
        cut_codeunits = nextind(preview, index) - 1
        cut_codeunits >= limit && continue

        if !splits_ascii_word(preview, cut_codeunits)
            return cut_codeunits
        end
    end

    return last_candidate
end

"""
Return a preview truncated to the display width.
"""
function truncate_preview(preview::AbstractString)
    preview = String(preview)
    cut_codeunits = preview_truncation_codeunits(preview)
    cut_codeunits >= ncodeunits(preview) && return preview
    cut_codeunits == 0 && return "…"

    return preview[firstindex(preview):prevind(preview, cut_codeunits + 1)] * "…"
end

"""
Return the parse mode for a handle record, falling back to text behavior.
"""
function handle_preview_parse_as(record::HandleRecord)
    file = record.file

    if file !== nothing
        cache = get(STATE[].files, file, nothing)
        cache !== nothing && return cache.parse_as
    end

    return :text
end

"""
Render a triple-quoted Julia string as an approximate single-line string.
"""
function compact_julia_triple_quoted_string(match::AbstractString)
    content = chop(String(match); head=3, tail=3)
    content = replace(content, '\\' => "\\\\", '"' => "\\\"", r"\s+" => " ")
    return "\"" * strip(content) * "\""
end

"""
Compact triple-quoted Julia strings before line-oriented preview formatting.
"""
function compact_julia_triple_quoted_strings(text::AbstractString)
    return replace(String(text), r"(?s)\"\"\".*?\"\"\"" => compact_julia_triple_quoted_string)
end

"""
Remove a Julia line comment unless it appears inside a simple string or char literal.
"""
function strip_julia_preview_comment(line::AbstractString)
    in_string = false
    in_char = false
    escaped = false

    for index in eachindex(line)
        char = line[index]

        if in_string
            if escaped
                escaped = false
            elseif char == '\\'
                escaped = true
            elseif char == '"'
                in_string = false
            end
        elseif in_char
            if escaped
                escaped = false
            elseif char == '\\'
                escaped = true
            elseif char == '\''
                in_char = false
            end
        elseif char == '#'
            return index == firstindex(line) ? "" : String(line[firstindex(line):prevind(line, index)])
        elseif char == '"'
            in_string = true
        elseif char == '\''
            in_char = true
        end
    end

    return String(line)
end

"""
Update delimiter depth for deciding whether a newline separates statements.
"""
function update_julia_preview_depth(line::AbstractString, depth::Integer)
    next_depth = Int(depth)
    in_string = false
    in_char = false
    escaped = false

    for char in line
        if in_string
            if escaped
                escaped = false
            elseif char == '\\'
                escaped = true
            elseif char == '"'
                in_string = false
            end
        elseif in_char
            if escaped
                escaped = false
            elseif char == '\\'
                escaped = true
            elseif char == '\''
                in_char = false
            end
        elseif char == '"'
            in_string = true
        elseif char == '\''
            in_char = true
        elseif char in ('(', '[', '{')
            next_depth += 1
        elseif char in (')', ']', '}')
            next_depth = max(next_depth - 1, 0)
        end
    end

    return next_depth
end

"""
Return an approximate one-line Julia representation of source code.
"""
function julia_oneline_preview(text::AbstractString)
    source = compact_julia_triple_quoted_strings(text)
    io = IOBuffer()
    separator = ""
    depth = 0

    for raw_line in split(source, '\n'; keepempty=true)
        line = strip(strip_julia_preview_comment(raw_line))
        isempty(line) && continue

        print(io, separator, line)
        depth = update_julia_preview_depth(line, depth)
        separator = depth > 0 ? " " : "; "
    end

    preview = String(take!(io))
    preview = replace(preview, r"[ \t]+" => " ")
    preview = replace(
        preview,
        "( " => "(",
        " )" => ")",
        "[ " => "[",
        " ]" => "]",
        "{ " => "{",
        " }" => "}",
        " ," => ",",
    )

    return strip(preview)
end

"""
Return the old single-line text preview of handle contents.
"""
function text_handle_preview(record::HandleRecord)
    return replace(strip(record.text), r"\n[ \t]*" => " ")
end

"""
Return a single-line preview of handle contents.
"""
function handle_preview(record::HandleRecord)
    preview = handle_preview_parse_as(record) == :julia ? julia_oneline_preview(record.text) : text_handle_preview(record)
    return truncate_preview(preview)
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
