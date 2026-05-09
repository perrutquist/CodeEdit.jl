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

"""
Final filesystem/content effect for one logical or path-only file.
"""
struct FileEditEffect
    key::Union{Nothing,FileKey}
    original_path::Union{Nothing,String}
    path::String
    parse_as::Symbol
    stamp::Union{Nothing,FileStamp}
    old_text::Union{Nothing,String}
    new_text::Union{Nothing,String}
    created::Bool
    deleted::Bool
    handle_spans::Dict{Int,Union{Nothing,Span}}
end

"""
Executable ordered edit plan for combined and file-level edits.
"""
struct EditPlan
    edit::AbstractEdit
    effects::Vector{FileEditEffect}
    moves::Vector{Tuple{String,String}}
    deletes::Vector{String}
    ordered_steps::Vector{String}
    valid::Bool
    errors::Vector{String}
    fingerprint::String
    display_text::String
end

mutable struct VirtualFileState
    key::Union{Nothing,FileKey}
    original_path::Union{Nothing,String}
    path::String
    parse_as::Symbol
    stamp::Union{Nothing,FileStamp}
    original_text::Union{Nothing,String}
    text::Union{Nothing,String}
    created::Bool
    deleted::Bool
    handle_spans::Dict{Int,Union{Nothing,Span}}
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

flatten_edits(edit::AbstractEdit) = AbstractEdit[edit]

function flatten_edits(edit::Combine)
    result = AbstractEdit[]

    for child in edit.edits
        append!(result, flatten_edits(child))
    end

    return result
end

function plan_error(edit::AbstractEdit, message::AbstractString, steps::Vector{String}=String[])
    fingerprint = sha1_hex(join(vcat(steps, String[message]), "\0"))
    return EditPlan(edit, FileEditEffect[], Tuple{String,String}[], String[], steps, false, String[message], fingerprint, "Validation errors:\n- $message\n")
end

function current_path_exists(path::AbstractString, virtual_by_path::Dict{String,VirtualFileState})
    abs_path = absolute_path(path)

    if haskey(virtual_by_path, abs_path)
        return !virtual_by_path[abs_path].deleted
    end

    return ispath(abs_path)
end

function virtual_file_for_handle!(
    handle::Handle,
    virtual_by_key::Dict{FileKey,VirtualFileState},
    virtual_by_path::Dict{String,VirtualFileState},
)
    record = valid_handle_record(handle)
    key = record.file
    key === nothing && throw(ArgumentError("invalid handle"))

    if haskey(virtual_by_key, key)
        vf = virtual_by_key[key]
        vf.deleted && throw(ArgumentError("file was deleted earlier in combined edit: $(vf.path)"))
        get(vf.handle_spans, handle.id, nothing) === nothing && throw(ArgumentError("handle was invalidated earlier in combined edit"))
        return vf
    end

    cache = STATE[].files[key]
    cache = load_file(cache.primary_path; parse_as=cache.parse_as)
    handle_spans = Dict{Int,Union{Nothing,Span}}()

    for id in cache.handles
        rec = handle_record(Handle(id))
        rec !== nothing && rec.valid && (handle_spans[id] = rec.span)
    end

    vf = VirtualFileState(
        cache.key,
        cache.primary_path,
        cache.primary_path,
        cache.parse_as,
        cache.stamp,
        cache.text,
        cache.text,
        false,
        false,
        handle_spans,
    )
    virtual_by_key[key] = vf
    virtual_by_path[vf.path] = vf
    return vf
end

function virtual_file_for_existing_path!(
    path::AbstractString,
    virtual_by_key::Dict{FileKey,VirtualFileState},
    virtual_by_path::Dict{String,VirtualFileState},
)
    abs_path = absolute_path(path)

    if haskey(virtual_by_path, abs_path)
        return virtual_by_path[abs_path]
    end

    info = read_source_file(abs_path)
    key = get(STATE[].id_index, info.id, nothing)

    if key !== nothing && haskey(STATE[].files, key)
        cache = load_file(abs_path; parse_as=STATE[].files[key].parse_as)
        handle_spans = Dict{Int,Union{Nothing,Span}}()

        for id in cache.handles
            rec = handle_record(Handle(id))
            rec !== nothing && rec.valid && (handle_spans[id] = rec.span)
        end

        vf = VirtualFileState(key, cache.primary_path, abs_path, cache.parse_as, cache.stamp, cache.text, cache.text, false, false, handle_spans)
        virtual_by_key[key] = vf
        virtual_by_path[abs_path] = vf
        return vf
    end

    parse_as = parse_mode_for_path(abs_path)
    text = info.text
    vf = VirtualFileState(nothing, abs_path, abs_path, parse_as, info.stamp, text, text, false, false, Dict{Int,Union{Nothing,Span}}())
    virtual_by_path[abs_path] = vf
    return vf
end

function replace_virtual_text!(vf::VirtualFileState, span::Span, code::AbstractString, target::Union{Nothing,Handle}, operation::Symbol)
    vf.text === nothing && throw(ArgumentError("cannot edit deleted file: $(vf.path)"))
    old_text = vf.text
    validate_span(old_text, span)
    new_text = replacement_text(old_text, span, code)
    delta = ncodeunits(code) - (span.hi - span.lo)
    target_id = target === nothing ? 0 : target.id

    for (id, old_span) in collect(vf.handle_spans)
        old_span === nothing && continue

        if operation == :delete && id == target_id
            vf.handle_spans[id] = old_span.lo == old_span.hi ? old_span : nothing
        elseif operation in (:replace, :replace_eof) && id == target_id
            vf.handle_spans[id] = Span(span.lo, span.lo + ncodeunits(code))
        elseif span.lo == span.hi
            if old_span.lo == old_span.hi == span.lo
                vf.handle_spans[id] = Span(old_span.lo + delta, old_span.hi + delta)
            elseif old_span.hi <= span.lo
                vf.handle_spans[id] = old_span
            elseif old_span.lo >= span.lo
                vf.handle_spans[id] = Span(old_span.lo + delta, old_span.hi + delta)
            else
                vf.handle_spans[id] = nothing
            end
        elseif old_span.hi <= span.lo
            vf.handle_spans[id] = old_span
        elseif old_span.lo >= span.hi
            vf.handle_spans[id] = Span(old_span.lo + delta, old_span.hi + delta)
        else
            vf.handle_spans[id] = nothing
        end
    end

    vf.text = new_text
    return vf
end

function replacement_for_virtual_edit(edit::Replace, span::Span)
    span.lo == span.hi && return (span = span, code = edit.code, operation = :replace_eof)
    return (span = span, code = edit.code, operation = :replace)
end

function replacement_for_virtual_edit(edit::Delete, span::Span)
    span.lo == span.hi && return (span = span, code = "", operation = :delete_eof)
    return (span = span, code = "", operation = :delete)
end

function replacement_for_virtual_edit(edit::InsertBefore, span::Span)
    return (span = Span(span.lo, span.lo), code = edit.code, operation = :insert_before)
end

function replacement_for_virtual_edit(edit::InsertAfter, span::Span)
    return (span = Span(span.hi, span.hi), code = edit.code, operation = :insert_after)
end

function interpret_content_edit!(
    edit::Union{Replace,Delete,InsertBefore,InsertAfter},
    virtual_by_key::Dict{FileKey,VirtualFileState},
    virtual_by_path::Dict{String,VirtualFileState},
    steps::Vector{String},
)
    handle = target_handle(edit)
    vf = virtual_file_for_handle!(handle, virtual_by_key, virtual_by_path)
    span = get(vf.handle_spans, handle.id, nothing)
    span === nothing && throw(ArgumentError("handle was invalidated earlier in combined edit"))
    replacement = replacement_for_virtual_edit(edit, span)
    replace_virtual_text!(vf, replacement.span, replacement.code, handle, replacement.operation)
    push!(steps, "$(replacement.operation):$(vf.path):$(replacement.span.lo):$(replacement.span.hi):$(sha1_hex(replacement.code))")
    return nothing
end

function interpret_create_file!(
    edit::CreateFile,
    virtual_by_path::Dict{String,VirtualFileState},
    steps::Vector{String},
)
    path = absolute_path(edit.path)
    current_path_exists(path, virtual_by_path) && throw(ArgumentError("file already exists: $path"))
    isdir(dirname(path)) || throw(ArgumentError("parent directory does not exist: $(dirname(path))"))
    parse_as = parse_mode_for_path(path; parse_as=edit.parse_as)
    vf = VirtualFileState(nothing, nothing, path, parse_as, nothing, nothing, edit.code, true, false, Dict{Int,Union{Nothing,Span}}())
    virtual_by_path[path] = vf
    push!(steps, "create:$path:$parse_as:$(sha1_hex(edit.code))")
    return nothing
end

function interpret_move_file!(
    edit::MoveFile,
    virtual_by_key::Dict{FileKey,VirtualFileState},
    virtual_by_path::Dict{String,VirtualFileState},
    moves::Vector{Tuple{String,String}},
    steps::Vector{String},
)
    old_path = absolute_path(edit.old_path)
    new_path = absolute_path(edit.new_path)
    reject_symlink_path(old_path, "move")
    is_symlink_path(new_path) && error("cannot move through symlink path: $new_path")
    current_path_exists(old_path, virtual_by_path) || throw(ArgumentError("file does not exist: $old_path"))
    current_path_exists(new_path, virtual_by_path) && throw(ArgumentError("destination already exists: $new_path"))
    isdir(dirname(new_path)) || throw(ArgumentError("parent directory does not exist: $(dirname(new_path))"))

    vf = virtual_file_for_existing_path!(old_path, virtual_by_key, virtual_by_path)
    vf.deleted && throw(ArgumentError("file was deleted earlier in combined edit: $old_path"))
    delete!(virtual_by_path, old_path)
    vf.path = new_path
    virtual_by_path[new_path] = vf
    push!(moves, (old_path, new_path))
    push!(steps, "move:$old_path:$new_path")
    return nothing
end

function interpret_delete_file!(
    edit::DeleteFile,
    virtual_by_key::Dict{FileKey,VirtualFileState},
    virtual_by_path::Dict{String,VirtualFileState},
    deletes::Vector{String},
    steps::Vector{String},
)
    path = absolute_path(edit.path)
    reject_symlink_path(path, "delete")
    current_path_exists(path, virtual_by_path) || throw(ArgumentError("file does not exist: $path"))

    vf = virtual_file_for_existing_path!(path, virtual_by_key, virtual_by_path)
    vf.deleted = true
    vf.text = nothing

    for id in keys(vf.handle_spans)
        vf.handle_spans[id] = nothing
    end

    delete!(virtual_by_path, path)
    push!(deletes, path)
    push!(steps, "delete_file:$path")
    return nothing
end

function effect_validation_errors(effect::FileEditEffect)
    effect.deleted && return String[]
    effect.new_text === nothing && return String[]
    return validation_errors(effect.new_text, effect.parse_as, effect.path)
end

function build_edit_plan(edit::AbstractEdit, edits::Vector{AbstractEdit})
    isempty(edits) && return plan_error(edit, "empty Combine edits are not supported")

    virtual_by_key = Dict{FileKey,VirtualFileState}()
    virtual_by_path = Dict{String,VirtualFileState}()
    moves = Tuple{String,String}[]
    deletes = String[]
    steps = String[]

    try
        for child in edits
            if child isa Union{Replace,Delete,InsertBefore,InsertAfter}
                interpret_content_edit!(child, virtual_by_key, virtual_by_path, steps)
            elseif child isa CreateFile
                interpret_create_file!(child, virtual_by_path, steps)
            elseif child isa MoveFile
                interpret_move_file!(child, virtual_by_key, virtual_by_path, moves, steps)
            elseif child isa DeleteFile
                interpret_delete_file!(child, virtual_by_key, virtual_by_path, deletes, steps)
            else
                throw(ArgumentError("unsupported edit type: $(typeof(child))"))
            end
        end
    catch err
        return plan_error(edit, sprint(showerror, err), steps)
    end

    all_vfiles = VirtualFileState[]
    append!(all_vfiles, values(virtual_by_key))

    for vf in values(virtual_by_path)
        if vf.key === nothing || !haskey(virtual_by_key, vf.key)
            push!(all_vfiles, vf)
        end
    end

    unique_vfiles = VirtualFileState[]
    seen_objects = Set{UInt}()

    for vf in all_vfiles
        object_id = objectid(vf)
        object_id in seen_objects && continue
        push!(seen_objects, object_id)
        push!(unique_vfiles, vf)
    end

    effects = FileEditEffect[]
    errors = String[]

    for vf in unique_vfiles
        changed = vf.deleted || vf.created || vf.original_path != vf.path || vf.original_text != vf.text
        changed || continue

        effect = FileEditEffect(
            vf.key,
            vf.original_path,
            vf.path,
            vf.parse_as,
            vf.stamp,
            vf.original_text,
            vf.text,
            vf.created,
            vf.deleted,
            copy(vf.handle_spans),
        )
        append!(errors, effect_validation_errors(effect))
        push!(effects, effect)
    end

    valid = isempty(errors)
    payload = String[]

    append!(payload, steps)

    for effect in sort(effects; by=e -> e.path)
        push!(payload, string(effect.key === nothing ? 0 : effect.key.id))
        push!(payload, string(effect.original_path))
        push!(payload, effect.path)
        push!(payload, String(effect.parse_as))
        push!(payload, effect.created ? "created" : "existing")
        push!(payload, effect.deleted ? "deleted" : "survives")
        push!(payload, effect.old_text === nothing ? "" : sha1_hex(effect.old_text))
        push!(payload, effect.new_text === nothing ? "" : sha1_hex(effect.new_text))
        push!(payload, effect.stamp === nothing ? "" : bytes2hex(effect.stamp.hash))
    end

    fingerprint = sha1_hex(join(payload, "\0"))

    io = IOBuffer()

    for effect in sort(effects; by=e -> e.path)
        if effect.deleted
            println(io, "Edit deletes $(effect.path)")
        elseif effect.created
            println(io, "Edit creates $(effect.path):")
            print(io, classic_diff("", effect.new_text === nothing ? "" : effect.new_text))
        elseif effect.original_path !== nothing && effect.original_path != effect.path
            println(io, "Edit moves $(effect.original_path) -> $(effect.path)")
            if effect.old_text != effect.new_text
                println(io, "Edit modifies $(effect.path):")
                print(io, classic_diff(effect.old_text === nothing ? "" : effect.old_text, effect.new_text === nothing ? "" : effect.new_text))
            end
        else
            println(io, "Edit modifies $(effect.path):")
            print(io, classic_diff(effect.old_text === nothing ? "" : effect.old_text, effect.new_text === nothing ? "" : effect.new_text))
        end
    end

    if !valid
        println(io, "Validation errors:")
        for error in errors
            println(io, "- $error")
        end
    end

    return EditPlan(edit, effects, moves, deletes, steps, valid, errors, fingerprint, String(take!(io)))
end

function compile_edit_plan(edit::Combine)
    return build_edit_plan(edit, flatten_edits(edit))
end

function compile_edit_plan(edit::Union{CreateFile,MoveFile,DeleteFile})
    return build_edit_plan(edit, AbstractEdit[edit])
end

function compile_edit_plan(edit::AbstractEdit)
    return unsupported_plan(edit, "$(typeof(edit)) planning is not supported yet")
end
