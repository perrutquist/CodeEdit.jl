function short_commit_id(id::AbstractString)
    return first(id, min(7, length(id)))
end

function commit_display_summary(commits::Vector{CommitInfo})
    isempty(commits) && return ""

    if length(commits) == 1
        return "commit $(short_commit_id(only(commits).id))"
    end

    entries = String["$(commit.kind) $(short_commit_id(commit.id))" for commit in commits]
    return "commits $(join(entries, ", "))"
end

function changed_file_count(changes::Vector{FileChange})
    return length(unique(String[change.path for change in changes]))
end

function Base.show(io::IO, ::MIME"text/plain", result::ApplyResult)
    count = changed_file_count(result.changes)
    file_summary = count == 1 ? "1 file changed" : "$count files changed"
    commit_summary = commit_display_summary(result.commits)

    if isempty(commit_summary)
        print(io, "Applied: $file_summary")
    else
        print(io, "Applied: $file_summary, $commit_summary")
    end
end

function Base.show(io::IO, result::ApplyResult)
    show(io, MIME"text/plain"(), result)
end

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
Return the paths affected by an executable edit plan.
"""
affected_paths(plan::ReplacementEditPlan) = String[absolute_path(plan.path)]

function affected_paths(plan::EditPlan)
    paths = String[]

    for effect in plan.effects
        effect.original_path !== nothing && push!(paths, absolute_path(effect.original_path))
        push!(paths, absolute_path(effect.path))
    end

    return unique(paths)
end

function created_paths(plan::ReplacementEditPlan)
    return String[]
end

function created_paths(plan::EditPlan)
    return unique(String[absolute_path(effect.path) for effect in plan.effects if effect.created])
end

function existing_versioned_paths(plan::ReplacementEditPlan)
    return String[absolute_path(plan.path)]
end

function existing_versioned_paths(plan::EditPlan)
    paths = String[]

    for effect in plan.effects
        if effect.created
            continue
        elseif effect.original_path !== nothing
            push!(paths, absolute_path(effect.original_path))
        else
            push!(paths, absolute_path(effect.path))
        end
    end

    return unique(paths)
end

function applied_file_changes(plan::ReplacementEditPlan)
    return FileChange[FileChange(absolute_path(plan.path), nothing, :modified)]
end

function effect_action(effect::FileEditEffect)
    if effect.created
        return :created
    elseif effect.deleted
        return :deleted
    elseif effect.original_path !== nothing && effect.original_path != effect.path
        return effect.new_text !== nothing && effect.old_text != effect.new_text ? :moved_modified : :moved
    elseif effect.new_text !== nothing && effect.old_text != effect.new_text
        return :modified
    end

    return :unchanged
end

function applied_file_changes(plan::EditPlan)
    changes = FileChange[]

    for effect in plan.effects
        original_path = effect.original_path === nothing ? nothing : absolute_path(effect.original_path)
        push!(changes, FileChange(absolute_path(effect.path), original_path, effect_action(effect)))
    end

    return changes
end

function assert_plan_valid(plan)
    plan.valid && return nothing
    message = isempty(plan.errors) ? "edit is invalid" : "edit is invalid: $(join(plan.errors, "; "))"
    error(message)
end

function compile_checked_plan(edit::AbstractEdit; require_view::Bool)
    if require_view
        displayed = edit.displayed[]
        displayed === nothing && error("edit has not been displayed")
        displayed.valid || error("displayed edit was invalid")

        plan = compile_edit_plan(edit)
        plan.valid || error("displayed edit was invalid")
        plan.fingerprint == displayed.fingerprint ||
            error("file changed since edit was displayed; display the edit again")
        return plan
    end

    plan = compile_edit_plan(edit)
    assert_plan_valid(plan)
    return plan
end

function run_after_apply_hooks!()
    try
        maybe_revise()
    catch err
        @warn "Revise failed after apply" exception=(err, catch_backtrace())
    end

    return nothing
end

function apply_compiled_plan!(plan)
    apply_plan!(plan)
    run_after_apply_hooks!()
    return nothing
end

function format_paths!(paths::Vector{String}, formatter)
    changed = String[]

    for path in unique(paths)
        isfile(path) || continue
        old_text = read(path, String)
        new_text = formatter(old_text)
        new_text isa AbstractString ||
            throw(ArgumentError("formatter must return an AbstractString for $path"))

        if old_text != new_text
            atomic_write(path, String(new_text))
            push!(changed, path)
        end
    end

    if !isempty(changed)
        try
            reindex()
        catch err
            @warn "Reindexing failed after formatting; chosen formatter may be incompatible with CodeEdit handles" exception=(err, catch_backtrace())
        end
    end

    return changed
end

function merged_apply_kwargs(vc::VersionControl, kwargs)
    return merge(vc.kwargs, (; kwargs...))
end

function option(options::NamedTuple, name::Symbol, default)
    return get(options, name, default)
end

function git_cmd(repo_root::AbstractString, args::Vector{String})
    return Cmd(vcat(String["git", "-C", String(repo_root)], args))
end

function git_run(repo_root::AbstractString, args::Vector{String})
    run(git_cmd(repo_root, args))
    return nothing
end

function git_success(repo_root::AbstractString, args::Vector{String})
    return success(ignorestatus(git_cmd(repo_root, args)))
end

function git_read(repo_root::AbstractString, args::Vector{String})
    return read(git_cmd(repo_root, args), String)
end

function git_commit_id(repo_root::AbstractString)
    return strip(git_read(repo_root, String["rev-parse", "HEAD"]))
end

function git_worktree_root(path::AbstractString)
    LibGit2.GitRepo(path)
    root = strip(git_read(path, String["rev-parse", "--show-toplevel"]))
    isempty(root) && error("could not determine git worktree root for $path")
    return canonical_path(root)
end

function path_in_worktree(path::AbstractString, repo_root::AbstractString)
    rel = relpath(comparable_path(path), comparable_path(repo_root))
    return rel != ".." && !startswith(rel, "..$(Base.Filesystem.path_separator)") && !isabspath(rel)
end

function repo_relative_path(path::AbstractString, repo_root::AbstractString)
    path_in_worktree(path, repo_root) || error("path is outside git worktree: $path")
    return relpath(canonical_path(path), canonical_path(repo_root))
end

function repo_relative_paths(paths::Vector{String}, repo_root::AbstractString)
    return String[repo_relative_path(path, repo_root) for path in unique(paths)]
end

function is_tracked(repo_root::AbstractString, path::AbstractString)
    rel = repo_relative_path(path, repo_root)
    return git_success(repo_root, String["ls-files", "--error-unmatch", "--", rel])
end

function status_dirty(repo_root::AbstractString, rels::Vector{String}; tracked_only::Bool=true)
    args = tracked_only ?
        vcat(String["status", "--porcelain", "--untracked-files=no", "--"], rels) :
        vcat(String["status", "--porcelain", "--"], rels)
    return !isempty(strip(git_read(repo_root, args)))
end

function staged_dirty(repo_root::AbstractString, rels::Vector{String})
    args = isempty(rels) ? String["diff", "--cached", "--quiet"] : vcat(String["diff", "--cached", "--quiet", "--"], rels)
    return !git_success(repo_root, args)
end

function stage_all!(repo_root::AbstractString, rels::Vector{String})
    isempty(rels) && return nothing
    git_run(repo_root, vcat(String["add", "-A", "--"], rels))
    return nothing
end

function stage_tracked!(repo_root::AbstractString, rels::Vector{String})
    args = isempty(rels) ? String["add", "-u"] : vcat(String["add", "-u", "--"], rels)
    git_run(repo_root, args)
    return nothing
end

function commit_staged!(repo_root::AbstractString, message::AbstractString, rels::Vector{String}=String[])
    staged_dirty(repo_root, rels) || return nothing
    args = isempty(rels) ? String["commit", "-m", String(message)] : vcat(String["commit", "-m", String(message), "--"], rels)
    git_run(repo_root, args)
    return git_commit_id(repo_root)
end

function assert_versioning_requirements(plan, repo_root::AbstractString; require_versioning::Bool)
    for path in affected_paths(plan)
        path_in_worktree(path, repo_root) || error("edit affects path outside git worktree: $path")
    end

    require_versioning || return nothing

    for path in existing_versioned_paths(plan)
        is_tracked(repo_root, path) || error("file is not under version control: $path")
    end

    for path in created_paths(plan)
        path_in_worktree(path, repo_root) || error("created file is outside git worktree: $path")
    end

    return nothing
end

function maybe_precommit_dirty!(
    repo_root::AbstractString,
    rels::Vector{String};
    require_clean::Bool,
    atomic_repo::Bool,
    precommit_message,
)
    scope_rels = atomic_repo ? String[] : rels
    dirty = status_dirty(repo_root, scope_rels; tracked_only=true)
    dirty || return nothing

    if require_clean
        error("tracked files have uncommitted changes")
    end

    precommit_message === nothing && error("precommit_message is required when applying over dirty tracked files")
    message = String(precommit_message)
    stage_tracked!(repo_root, scope_rels)
    commit_id = commit_staged!(repo_root, message, scope_rels)
    return commit_id === nothing ? nothing : CommitInfo(:precommit, commit_id, message)
end

function commit_formatting!(
    repo_root::AbstractString,
    changed_paths::Vector{String},
    message::AbstractString,
)
    isempty(changed_paths) && return nothing
    rels = repo_relative_paths(changed_paths, repo_root)
    stage_all!(repo_root, rels)
    commit_id = commit_staged!(repo_root, message, rels)
    return commit_id === nothing ? nothing : CommitInfo(:format, commit_id, message)
end

"""
    apply!(edit::AbstractEdit)

Reject edits applied without an explicit version-control specification.

Use `apply!(NoVersionControl(require_view=true), edit)` for behavior equivalent
to the old `apply!(edit)`, or `apply!(VersionControl(path), edit, message)` to
apply and commit an edit in a git repository.
"""
function apply!(edit::AbstractEdit)
    error("apply! requires a VersionControl specification; use apply!(NoVersionControl(require_view=true), edit) or apply!(VersionControl(path), edit, message)")
end

function apply!(vc::VersionControl{:none}, edit::AbstractEdit; kwargs...)
    options = merged_apply_kwargs(vc, kwargs)
    require_view = option(options, :require_view, false)
    formatter = option(options, :formatter, nothing)
    preformat = option(options, :preformat, true)

    initial_plan = compile_checked_plan(edit; require_view=require_view)
    formatted_paths = String[]

    if formatter !== nothing && preformat
        formatted_paths = format_paths!(affected_paths(initial_plan), formatter)
    end

    plan = formatter !== nothing && preformat ? compile_checked_plan(edit; require_view=false) : initial_plan
    apply_compiled_plan!(plan)
    return ApplyResult(:none, applied_file_changes(plan), CommitInfo[], plan.display_text, formatted_paths)
end

function apply!(vc::VersionControl{:none}, edit::AbstractEdit, message::AbstractString; kwargs...)
    return apply!(vc, edit; kwargs...)
end

function apply!(vc::VersionControl{:git}, edit::AbstractEdit; kwargs...)
    options = merged_apply_kwargs(vc, kwargs)
    default_message = option(options, :default_message, nothing)
    default_message === nothing && error("commit message required; pass apply!(repo, edit, message) or set default_message")
    return apply!(vc, edit, String(default_message); kwargs...)
end

function apply!(vc::VersionControl{:git}, edit::AbstractEdit, message::AbstractString; kwargs...)
    options = merged_apply_kwargs(vc, kwargs)

    repo_root = git_worktree_root(vc.repo_path)
    require_view = option(options, :require_view, false)
    require_versioning = option(options, :require_versioning, true)
    precommit_message = option(options, :precommit_message, nothing)
    require_clean = option(options, :require_clean, precommit_message === nothing)
    atomic_repo = option(options, :atomic_repo, false)
    formatter = option(options, :formatter, nothing)
    preformat = option(options, :preformat, true)
    format_message = option(options, :format_message, "Automatic formatting by $formatter.")

    initial_plan = compile_checked_plan(edit; require_view=require_view)
    assert_versioning_requirements(initial_plan, repo_root; require_versioning=require_versioning)
    rels = repo_relative_paths(affected_paths(initial_plan), repo_root)

    precommit = maybe_precommit_dirty!(
        repo_root,
        rels;
        require_clean=require_clean,
        atomic_repo=atomic_repo,
        precommit_message=precommit_message,
    )

    formatted_paths = String[]
    format_commit = nothing

    if formatter !== nothing && preformat
        formatted_paths = format_paths!(affected_paths(initial_plan), formatter)
        format_commit = commit_formatting!(repo_root, formatted_paths, String(format_message))
    end

    plan = formatter !== nothing && preformat ? compile_checked_plan(edit; require_view=false) : initial_plan
    assert_versioning_requirements(plan, repo_root; require_versioning=require_versioning)

    apply_plan!(plan)
    run_after_apply_hooks!()

    final_rels = repo_relative_paths(affected_paths(plan), repo_root)
    stage_all!(repo_root, final_rels)
    edit_commit_id = commit_staged!(repo_root, message, final_rels)

    commits = CommitInfo[]
    precommit !== nothing && push!(commits, precommit)
    format_commit !== nothing && push!(commits, format_commit)
    edit_commit_id !== nothing && push!(commits, CommitInfo(:edit, edit_commit_id, message))

    return ApplyResult(:git, applied_file_changes(plan), commits, plan.display_text, formatted_paths)
end
