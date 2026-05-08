"""
Executable plan for one handle-based content replacement.
"""
struct ReplacementEditPlan
    edit::AbstractEdit
    key::FileKey
    path::String
    parse_as::Symbol
    stamp::FileStamp
    span::Span
    code::String
    old_text::String
    new_text::String
    target::Handle
    operation::Symbol
    valid::Bool
    errors::Vector{String}
    fingerprint::String
    display_text::String
end

sha1_hex(text::AbstractString) = bytes2hex(sha1(Vector{UInt8}(codeunits(text))))

function replacement_text(text::AbstractString, span::Span, code::AbstractString)
    validate_span(text, span)

    before = span.lo == firstindex(text) ? "" : String(text[firstindex(text):prevind(text, span.lo)])
    after = span.hi > ncodeunits(text) ? "" : String(text[span.hi:end])
    return before * String(code) * after
end

function plan_fingerprint(
    edit_type::Symbol,
    key::FileKey,
    path::AbstractString,
    parse_as::Symbol,
    stamp::FileStamp,
    span::Span,
    code::AbstractString,
    old_text::AbstractString,
    new_text::AbstractString,
)
    payload = join(
        String[
            String(edit_type),
            string(key.id),
            String(path),
            String(parse_as),
            string(stamp.mtime),
            string(stamp.size),
            bytes2hex(stamp.hash),
            string(span.lo),
            string(span.hi),
            sha1_hex(code),
            sha1_hex(old_text),
            sha1_hex(new_text),
        ],
        "\0",
    )

    return sha1_hex(payload)
end

function validation_errors(text::AbstractString, parse_as::Symbol, path::AbstractString)
    errors = String[]

    try
        validate_utf8(Vector{UInt8}(codeunits(text)), path)
        parse_as == :julia && validate_julia_parse(text, path)
    catch err
        push!(errors, sprint(showerror, err))
    end

    return errors
end

function replacement_for_edit(edit::Replace, record::HandleRecord)
    record.span.lo == record.span.hi && return (span = record.span, code = edit.code, operation = :replace_eof)
    return (span = record.span, code = edit.code, operation = :replace)
end

function replacement_for_edit(edit::Delete, record::HandleRecord)
    record.span.lo == record.span.hi && return (span = record.span, code = "", operation = :delete_eof)
    return (span = record.span, code = "", operation = :delete)
end

function replacement_for_edit(edit::InsertBefore, record::HandleRecord)
    return (span = Span(record.span.lo, record.span.lo), code = edit.code, operation = :insert_before)
end

function replacement_for_edit(edit::InsertAfter, record::HandleRecord)
    return (span = Span(record.span.hi, record.span.hi), code = edit.code, operation = :insert_after)
end

target_handle(edit::Replace) = edit.handle
target_handle(edit::Delete) = edit.handle
target_handle(edit::InsertBefore) = edit.handle
target_handle(edit::InsertAfter) = edit.handle

function unsupported_plan(edit::AbstractEdit, message::AbstractString)
    return ReplacementEditPlan(
        edit,
        FileKey(0),
        "",
        :text,
        FileStamp(0.0, 0, UInt8[]),
        Span(1, 1),
        "",
        "",
        "",
        Handle(0),
        :unsupported,
        false,
        String[message],
        sha1_hex(message),
        "Unsupported edit: $message\n",
    )
end

function compile_content_edit_plan(edit::AbstractEdit)
    handle = target_handle(edit)
    record = valid_handle_record(handle)
    key = record.file
    key === nothing && throw(ArgumentError("invalid handle"))

    cache = STATE[].files[key]
    load_file(cache.primary_path; parse_as=cache.parse_as)
    record = valid_handle_record(handle)
    cache = STATE[].files[record.file]

    replacement = replacement_for_edit(edit, record)
    new_text = replacement_text(cache.text, replacement.span, replacement.code)
    errors = validation_errors(new_text, cache.parse_as, cache.primary_path)
    valid = isempty(errors)

    fingerprint = plan_fingerprint(
        replacement.operation,
        cache.key,
        cache.primary_path,
        cache.parse_as,
        cache.stamp,
        replacement.span,
        replacement.code,
        cache.text,
        new_text,
    )

    io = IOBuffer()
    println(io, "Edit modifies $(cache.primary_path):")
    print(io, classic_diff(cache.text, new_text))

    if !valid
        println(io, "Validation errors:")
        for error in errors
            println(io, "- $error")
        end
    end

    return ReplacementEditPlan(
        edit,
        cache.key,
        cache.primary_path,
        cache.parse_as,
        cache.stamp,
        replacement.span,
        String(replacement.code),
        cache.text,
        new_text,
        handle,
        replacement.operation,
        valid,
        errors,
        fingerprint,
        String(take!(io)),
    )
end

function compile_edit_plan(edit::Union{Replace,Delete,InsertBefore,InsertAfter})
    try
        return compile_content_edit_plan(edit)
    catch err
        message = sprint(showerror, err)
        return unsupported_plan(edit, message)
    end
end

function compile_edit_plan(edit::Combine)
    isempty(edit.edits) && return unsupported_plan(edit, "empty Combine edits are not supported yet")
    return unsupported_plan(edit, "ordered Combine planning is not supported yet")
end

function compile_edit_plan(edit::AbstractEdit)
    return unsupported_plan(edit, "$(typeof(edit)) planning is not supported yet")
end
