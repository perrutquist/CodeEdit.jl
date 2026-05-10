function store_displayed_plan!(edit::AbstractEdit, plan)
    edit.displayed[] = DisplayedPlan(plan.fingerprint, plan.valid, plan.display_text)
    return edit
end

"""
Set or clear the displayed marker for an edit.

When `displayed` is `true`, this compiles and validates the current edit plan
and stores its fingerprint as the plan approved for application. It does not
print the diff. Use this only when intentionally bypassing visible review.
"""
function displayed!(edit::AbstractEdit, displayed::Bool=true)
    if displayed
        plan = compile_edit_plan(edit)
        store_displayed_plan!(edit, plan)
    else
        edit.displayed[] = nothing
    end

    return edit
end

function is_valid(edit::Union{Replace,Delete,InsertBefore,InsertAfter})
    return compile_edit_plan(edit).valid
end

is_valid(edit::AbstractEdit) = compile_edit_plan(edit).valid

"""
    display(edit)
    string(edit)

Display an edit plan and mark that exact plan as displayed. `apply!` replans
the edit and refuses to apply it if the current plan differs from the displayed
plan.
"""
function Base.show(io::IO, ::MIME"text/plain", edit::AbstractEdit)
    plan = compile_edit_plan(edit)
    store_displayed_plan!(edit, plan)
    print(io, plan.display_text)
end

function Base.show(io::IO, edit::AbstractEdit)
    show(io, MIME"text/plain"(), edit)
end

function atomic_write(path::AbstractString, text::AbstractString)
    reject_symlink_path(path, "write")
    directory = dirname(String(path))
    temp = tempname(directory)

    try
        open(temp, "w") do io
            write(io, text)
            flush(io)
        end

        try
            chmod(temp, filemode(path))
        catch
        end

        mv(temp, path; force=true)
    catch
        ispath(temp) && rm(temp; force=true)
        rethrow()
    end

    return nothing
end

function transformed_record_span(record_id::Integer, record::HandleRecord, plan::ReplacementEditPlan)
    delta = ncodeunits(plan.code) - (plan.span.hi - plan.span.lo)

    if plan.operation == :delete && record_id == plan.target.id
        return nothing
    end

    if plan.operation == :replace && record_id == plan.target.id
        return Span(plan.span.lo, plan.span.lo + ncodeunits(plan.code))
    end

    if record.span.lo == record.span.hi == plan.span.lo == plan.span.hi
        return Span(record.span.lo + delta, record.span.hi + delta)
    end

    if record.span.hi <= plan.span.lo
        return record.span
    end

    if record.span.lo >= plan.span.hi
        return Span(record.span.lo + delta, record.span.hi + delta)
    end

    return nothing
end

function invalidate_record!(record::HandleRecord)
    record.valid = false
    record.file = nothing
    return record
end

function update_record_from_block!(
    record::HandleRecord,
    key::FileKey,
    block_index::Integer,
    block::Block,
    text::AbstractString,
)
    record.file = key
    record.block_index = Int(block_index)
    record.span = block.span
    record.lines = block.lines
    record.text = span_text(text, block.span)
    record.doc = nothing
    record.valid = true
    return record
end

function update_cache_after_replacement_plan!(plan::ReplacementEditPlan)
    state = STATE[]
    old_cache = state.files[plan.key]
    old_handle_ids = copy(old_cache.handles)
    old_records = Dict(id => state.handles[id] for id in old_handle_ids if haskey(state.handles, id))

    info = read_source_file(plan.path)
    blocks = parse_source_blocks(info.text, info.line_starts, plan.parse_as; path=plan.path)

    cache = FileCache(
        plan.key,
        info.id,
        plan.path,
        union(old_cache.paths, Set([plan.path])),
        info.stamp,
        plan.parse_as,
        info.text,
        info.line_starts,
        info.line_ending,
        blocks,
        fill(0, length(blocks)),
        old_cache.generation + 1,
    )

    span_index = Dict{Tuple{Int,Int},Vector{Int}}()
    for (index, block) in pairs(blocks)
        key = (block.span.lo, block.span.hi)
        push!(get!(span_index, key, Int[]), index)
    end

    assigned = falses(length(blocks))

    for id in old_handle_ids
        record = get(old_records, id, nothing)
        record === nothing && continue
        record.valid || continue

        new_span = transformed_record_span(id, record, plan)
        if new_span === nothing
            invalidate_record!(record)
            continue
        end

        candidates = get(span_index, (new_span.lo, new_span.hi), Int[])
        if length(candidates) == 1 && !assigned[only(candidates)]
            index = only(candidates)
            update_record_from_block!(record, plan.key, index, blocks[index], info.text)
            cache.handles[index] = id
            assigned[index] = true
        else
            invalidate_record!(record)
        end
    end

    for (index, block) in pairs(blocks)
        assigned[index] && continue

        record = HandleRecord(
            plan.key,
            plan.path,
            index,
            block.span,
            block.lines,
            span_text(info.text, block.span),
            nothing,
            true,
        )
        handle = register_handle!(record)
        cache.handles[index] = handle.id
    end

    state.files[plan.key] = cache
    state.path_index[plan.path] = plan.key
    state.id_index[cache.current_id] = plan.key
    return cache
end

function update_cache_after_effect!(effect::FileEditEffect)
    state = STATE[]

    if effect.key === nothing
        effect.deleted && return nothing
        effect.new_text === nothing && return nothing

        if isfile(effect.path)
            cache = load_file(effect.path; parse_as=effect.parse_as)
            return cache
        end

        return nothing
    end

    key = effect.key

    if effect.deleted
        if haskey(state.files, key)
            cache = state.files[key]
            delete!(state.path_index, cache.primary_path)

            for path in cache.paths
                delete!(state.path_index, path)
            end

            cache.current_id !== nothing && delete!(state.id_index, cache.current_id)
            delete!(state.files, key)
        end

        invalidate_file_handles!(key)
        return nothing
    end

    info = read_source_file(effect.path)
    blocks = parse_source_blocks(info.text, info.line_starts, effect.parse_as; path=effect.path)
    old_cache = get(state.files, key, nothing)
    old_paths = old_cache === nothing ? Set{String}() : setdiff(old_cache.paths, Set([something(effect.original_path, "")]))
    generation = old_cache === nothing ? 1 : old_cache.generation + 1

    cache = FileCache(
        key,
        info.id,
        effect.path,
        union(old_paths, Set([effect.path])),
        info.stamp,
        effect.parse_as,
        info.text,
        info.line_starts,
        info.line_ending,
        blocks,
        fill(0, length(blocks)),
        generation,
    )

    span_index = Dict{Tuple{Int,Int},Vector{Int}}()
    for (index, block) in pairs(blocks)
        push!(get!(span_index, (block.span.lo, block.span.hi), Int[]), index)
    end

    assigned = falses(length(blocks))

    for (id, span) in effect.handle_spans
        record = get(state.handles, id, nothing)
        record === nothing && continue

        if span === nothing
            invalidate_record!(record)
            continue
        end

        candidates = get(span_index, (span.lo, span.hi), Int[])

        if length(candidates) == 1 && !assigned[only(candidates)]
            index = only(candidates)
            update_record_from_block!(record, key, index, blocks[index], info.text)
            record.path = effect.path
            cache.handles[index] = id
            assigned[index] = true
        else
            invalidate_record!(record)
        end
    end

    for (index, block) in pairs(blocks)
        assigned[index] && continue

        record = HandleRecord(
            key,
            effect.path,
            index,
            block.span,
            block.lines,
            span_text(info.text, block.span),
            nothing,
            true,
        )
        handle = register_handle!(record)
        cache.handles[index] = handle.id
    end

    if effect.original_path !== nothing && effect.original_path != effect.path
        delete!(state.path_index, effect.original_path)
    end

    if old_cache !== nothing && old_cache.current_id !== nothing && old_cache.current_id != cache.current_id
        delete!(state.id_index, old_cache.current_id)
    end

    state.files[key] = cache
    state.path_index[effect.path] = key
    state.id_index[cache.current_id] = key
    return cache
end

function apply_plan!(plan::ReplacementEditPlan)
    atomic_write(plan.path, plan.new_text)
    update_cache_after_replacement_plan!(plan)
    return nothing
end

function apply_plan!(plan::EditPlan)
    for effect in plan.effects
        if effect.deleted
            effect.original_path !== nothing && ispath(effect.original_path) && rm(effect.original_path; force=true)
            update_cache_after_effect!(effect)
            continue
        end

        if effect.created
            open(effect.path, "w") do io
                write(io, effect.new_text === nothing ? "" : effect.new_text)
            end
            update_cache_after_effect!(effect)
            continue
        end

        if effect.original_path !== nothing && effect.original_path != effect.path
            mv(effect.original_path, effect.path; force=false)
        end

        if effect.new_text !== nothing && effect.old_text != effect.new_text
            atomic_write(effect.path, effect.new_text)
        end

        update_cache_after_effect!(effect)
    end

    return nothing
end

"""
    apply!(edit::AbstractEdit)

Apply a previously displayed edit to the filesystem.

The edit must have been displayed, either by printing, displaying, stringifying
it, or by calling [`displayed!`](@ref). The edit is replanned before application
and is rejected if the current plan no longer matches the displayed plan.

Combined edits are planned and validated as a unit, but applying a combined edit
that touches multiple files is best-effort at the filesystem level. If a later
operation fails, earlier file operations may already have been applied.
"""
function apply!(edit::AbstractEdit)
    displayed = edit.displayed[]
    displayed === nothing && error("edit has not been displayed")
    displayed.valid || error("displayed edit was invalid")

    plan = compile_edit_plan(edit)
    plan.valid || error("displayed edit was invalid")
    plan.fingerprint == displayed.fingerprint ||
        error("file changed since edit was displayed; display the edit again")

    apply_plan!(plan)

    try
        maybe_revise()
    catch err
        @warn "Revise failed after apply" exception=(err, catch_backtrace())
    end

    println("Success.")
    return nothing
end
