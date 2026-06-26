const _GLOB_MARKERS = Set(['*', '?', '['])

"""
Normalize the high-level parse-mode keyword.

The public UI prefers `as`; `parse_as` remains accepted for compatibility.
"""
function _normalize_parse_as(; as::Symbol=:auto, parse_as=nothing)
    mode = parse_as === nothing ? as : parse_as
    mode isa Symbol || throw(ArgumentError("as must be :auto, :julia, or :text"))

    if parse_as !== nothing && as != :auto && as != parse_as
        throw(ArgumentError("as and parse_as disagree"))
    end

    mode in VALID_PARSE_MODES || throw(ArgumentError("as must be :auto, :julia, or :text"))
    return mode
end

function _contains_glob(path::AbstractString)
    return any(char -> char in _GLOB_MARKERS, String(path))
end

function _is_under_path(path::AbstractString, root::AbstractString)
    rel = relpath(comparable_path(path), comparable_path(root))
    return rel == "." || (rel != ".." && !startswith(rel, "..$(Base.Filesystem.path_separator)") && !isabspath(rel))
end

function _walk_utf8_files(root::AbstractString)
    root_path = absolute_path(root)

    if isfile(root_path)
        return is_valid_utf8_file(root_path) ? String[root_path] : String[]
    end

    isdir(root_path) || return String[]

    paths = String[]

    for (dir, dirs, files) in walkdir(root_path)
        filter!(name -> name != ".git", dirs)

        for file in files
            path = joinpath(dir, file)
            is_valid_utf8_file(path) && push!(paths, absolute_path(path))
        end
    end

    return sort!(unique(paths))
end

function _glob_filter_paths(root::AbstractString, files)
    files === nothing && return nothing

    patterns = files isa AbstractString ? AbstractString[files] : collect(files)
    result = Set{String}()

    for pattern in patterns
        pattern_string = String(pattern)
        matches = isabspath(pattern_string) ? glob(pattern_string) : glob(pattern_string, root)

        for path in matches
            abs_path = absolute_path(path)
            isfile(abs_path) && is_valid_utf8_file(abs_path) && push!(result, abs_path)
        end
    end

    return result
end

function _workspace_paths(ws::Workspace; files=nothing)
    allowed = _glob_filter_paths(ws.root, files)

    paths = if ws.git
        repo_root = git_worktree_root(ws.vc.repo_path)
        String[
            path for path in git_tracked_paths(repo_root) if
            _is_under_path(path, ws.root) && isfile(path) && is_valid_utf8_file(path)
        ]
    else
        _walk_utf8_files(ws.root)
    end

    allowed === nothing || filter!(path -> path in allowed, paths)
    return sort!(unique(paths))
end

function _paths_for_path_or_glob(path_or_glob::AbstractString; files=nothing)
    text_path = String(path_or_glob)

    if files !== nothing
        root = isdir(text_path) ? absolute_path(text_path) : dirname(absolute_path(text_path))
        allowed = _glob_filter_paths(root, files)
        return allowed === nothing ? String[] : sort!(collect(allowed))
    end

    if _contains_glob(text_path)
        return sort!(unique(String[
            absolute_path(path) for path in glob(text_path) if
            isfile(path) && is_valid_utf8_file(path)
        ]))
    end

    abs_path = absolute_path(text_path)
    isdir(abs_path) && return _walk_utf8_files(abs_path)
    return String[abs_path]
end

function _workspace_vc(root::AbstractString, git)
    if git === false || git == :none
        return (false, NoVersionControl())
    elseif git === true || git == :required || git == :auto
        try
            git_root = git_worktree_root(root)
            return (true, GitVersionControl(git_root))
        catch err
            git == :auto && return (false, NoVersionControl())
            error("workspace is not inside a git worktree: $root")
        end
    end

    throw(ArgumentError("git must be :auto, :required, true, or false"))
end

"""
    workspace(path="."; git=:auto, review=true)

Create a high-level editing workspace.
"""
function workspace(path::AbstractString="."; git=:auto, review::Bool=true, require_view=nothing)
    root = absolute_path(path)
    review_value = require_view === nothing ? review : Bool(require_view)
    uses_git, vc = _workspace_vc(root, git)
    return Workspace(root, uses_git, review_value, vc)
end

repo(path::AbstractString="."; kwargs...) = workspace(path; kwargs...)
project(path::AbstractString="."; kwargs...) = workspace(path; kwargs...)
codebase(path::AbstractString="."; kwargs...) = workspace(path; kwargs...)

function Base.show(io::IO, ws::Workspace)
    print(io, "Workspace(")
    show(io, display_path(ws.root))
    print(io, "; git=$(ws.git), review=$(ws.review))")
end

"""
    blocks(workspace; files=nothing, as=:auto)
    blocks(path_or_glob; as=:auto, includes=false, follow_includes=includes)

Return user-facing source blocks.
"""
function blocks end

function blocks(
    ws::Workspace;
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    mode = _normalize_parse_as(as=as, parse_as=parse_as)
    result = Set{Handle}()

    for path in _workspace_paths(ws; files=files)
        union!(result, handles(path; includes=follow_includes, parse_as=mode))
    end

    return result
end

function blocks(
    path_or_glob::AbstractString;
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    mode = _normalize_parse_as(as=as, parse_as=parse_as)
    result = Set{Handle}()

    for path in _paths_for_path_or_glob(path_or_glob; files=files)
        union!(result, handles(path; includes=follow_includes, parse_as=mode))
    end

    return result
end

function blocks(
    paths::AbstractVector{<:AbstractString};
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    mode = _normalize_parse_as(as=as, parse_as=parse_as)
    result = Set{Handle}()

    for path in paths
        union!(result, blocks(path; as=mode, includes=includes, follow_includes=follow_includes))
    end

    return result
end

function blocks(trace::Vector{StackTraces.StackFrame}; kwargs...)
    ws = get(kwargs, :in, nothing)
    result = Handle[]
    seen = Set{Int}()

    for frame in trace
        handle = Handle(frame; return_invalid=true)
        is_valid(handle) || continue

        if ws isa Workspace && !_is_under_path(filepath(handle), ws.root)
            continue
        end

        handle.id in seen && continue
        push!(seen, handle.id)
        push!(result, handle)
    end

    return result
end

blocks(trace::Vector{Union{Ptr{Nothing}, Base.InterpreterIP}}; kwargs...) = blocks(stacktrace(trace); kwargs...)

handles(ws::Workspace; kwargs...) = blocks(ws; kwargs...)

"""
    block(selector; as=:auto)
    block(method)
    block(stackframe)

Return the source block selected by a `path:line` selector or Julia source
location metadata.
"""
function block(selector::AbstractString; as::Symbol=:auto, parse_as=nothing)
    mode = _normalize_parse_as(as=as, parse_as=parse_as)
    path_suffix, line, pos = _parse_handle_at_key(selector)
    return Handle(path_suffix, line, something(pos, 1); parse_as=mode)
end

block(method::Method; kwargs...) = Handle(method; kwargs...)
block(frame::StackTraces.StackFrame; kwargs...) = Handle(frame; kwargs...)

function Base.getindex(ws::Workspace, selector::AbstractString)
    return handle_at(blocks(ws), selector)
end

source(handle::Handle) = string(handle)
text(handle::Handle) = source(handle)
path(handle::Handle) = filepath(handle)
span(handle::Handle) = (path(handle), lines(handle))
docs(handle::Handle) = docstring(handle)

function replace(handle::Handle, replacement::Pair, replacements::Pair...; kwargs...)
    return Replace(handle, Base.replace(source(handle), replacement, replacements...; kwargs...))
end

function replace(handle::Handle, new_source::AbstractString)
    return Replace(handle, new_source)
end

function replace(collection::AbstractSet{Handle}, replacements::Pair...; kwargs...)
    return patch([replace(handle, replacements...; kwargs...) for handle in collection]...)
end

function replace(collection::AbstractVector{Handle}, replacements::Pair...; kwargs...)
    return patch([replace(handle, replacements...; kwargs...) for handle in collection]...)
end

delete(handle::Handle) = Delete(handle)

function delete(collection::AbstractSet{Handle})
    return patch([Delete(handle) for handle in collection]...)
end

function delete(collection::AbstractVector{Handle})
    return patch([Delete(handle) for handle in collection]...)
end

insert_before(handle::Handle, code::AbstractString) = InsertBefore(handle, code)
insert_after(handle::Handle, code::AbstractString) = InsertAfter(handle, code)

function append_to(path::AbstractString, code::AbstractString; as::Symbol=:auto, parse_as=nothing)
    mode = _normalize_parse_as(as=as, parse_as=parse_as)
    return InsertAfter(eof_handle(path; parse_as=mode), code)
end

function prepend_to(path::AbstractString, code::AbstractString; as::Symbol=:auto, parse_as=nothing)
    mode = _normalize_parse_as(as=as, parse_as=parse_as)
    cache = load_file(path; parse_as=mode)
    return InsertBefore(block_handle(cache, 1), code)
end

create_file(path::AbstractString, code::AbstractString; as::Symbol=:auto, parse_as=nothing) =
    CreateFile(path, code; parse_as=_normalize_parse_as(as=as, parse_as=parse_as))

move_file(old_path::AbstractString, new_path::AbstractString) = MoveFile(old_path, new_path)
delete_file(path::AbstractString) = DeleteFile(path)

patch(edits::AbstractEdit...) = Combine(edits...)
patch(edits::AbstractVector{<:AbstractEdit}) = Combine(edits)

Base.:+(a::AbstractEdit, b::AbstractEdit) = Combine(a, b)
Base.:+(a::Combine, b::AbstractEdit) = Combine(vcat(a.edits, AbstractEdit[b]), display_ref())
Base.:+(a::AbstractEdit, b::Combine) = Combine(vcat(AbstractEdit[a], b.edits), display_ref())

function preview(edit::AbstractEdit)
    io = IOBuffer()
    show(io, MIME"text/plain"(), edit)
    return String(take!(io))
end

diff(edit::AbstractEdit) = preview(edit)

edit(method::Method, args...; kwargs...) = replace(block(method), args...; kwargs...)

function _nearest_existing_parent(path::AbstractString)
    current = absolute_path(path)

    while !isdir(current)
        parent = dirname(current)
        parent == current && error("no existing parent directory for $path")
        current = parent
    end

    return current
end

function _git_probe_path(path::AbstractString)
    isdir(path) && return path
    ispath(path) && return dirname(path)
    return _nearest_existing_parent(dirname(path))
end

function _version_control_for_plan(plan, git)
    if git === false || git == :none
        return NoVersionControl()
    elseif !(git === true || git == :required || git == :auto)
        throw(ArgumentError("git must be :auto, :required, true, or false"))
    end

    roots = Set{String}()

    for path in affected_paths(plan)
        try
            push!(roots, git_worktree_root(_git_probe_path(path)))
        catch err
            error(
                "$path is not inside a git worktree\n\n" *
                "To write without committing, use:\n\n" *
                " apply!(patch; git=false)\n\n" *
                "To create a workspace that allows non-git edits, use:\n\n" *
                " ws = workspace(\".\"; git=false)"
            )
        end
    end

    isempty(roots) && return NoVersionControl()
    length(roots) == 1 || error("patch affects multiple git worktrees")
    return GitVersionControl(only(roots))
end

function _version_control_for_edit(edit::AbstractEdit, git)
    return _version_control_for_plan(compile_edit_plan(edit), git)
end

function _normalized_apply_kwargs(;
    review::Bool=true,
    require_view=nothing,
    precommit=nothing,
    precommit_message=nothing,
    dirty::Symbol=:reject,
    kwargs...,
)
    options = Dict{Symbol,Any}()

    for (key, value) in pairs(kwargs)
        options[key] = value
    end

    options[:require_view] = require_view === nothing ? true : Bool(require_view === nothing ? review : require_view)

    if precommit !== nothing
        precommit_message === nothing || throw(ArgumentError("use only one of precommit and precommit_message"))
        options[:precommit_message] = precommit
    elseif precommit_message !== nothing
        options[:precommit_message] = precommit_message
    end

    if dirty == :allow
        options[:require_clean] = false
    elseif dirty == :reject
        get!(options, :require_clean, true)
    else
        throw(ArgumentError("dirty must be :reject or :allow"))
    end

    return (; (key => value for (key, value) in options)...)
end

function _has_displayed_plan(edit::AbstractEdit)
    return getfield(edit, :displayed)[] !== nothing
end

function _review_if_needed!(edit::AbstractEdit; require_view::Bool, yes::Bool)
    require_view || return nothing
    _has_displayed_plan(edit) && return nothing

    display(edit)

    if isinteractive() && !yes
        print(stdout, "\nApply this patch? [y/N]: ")
        flush(stdout)
        answer = lowercase(strip(readline(stdin)))
        answer in ("y", "yes") || error("patch was not applied")
    elseif !yes
        error("patch has not been reviewed; pass yes=true or display the patch before applying")
    end

    return nothing
end

function _apply_with_vc!(
    vc::VersionControl,
    edit::AbstractEdit,
    message::Union{Nothing,AbstractString};
    review::Bool=true,
    require_view=nothing,
    yes::Bool=false,
    kwargs...,
)
    normalized = _normalized_apply_kwargs(; review=review, require_view=require_view, kwargs...)
    _review_if_needed!(edit; require_view=get(normalized, :require_view, false), yes=yes)

    if message === nothing
        return apply!(vc, edit; normalized...)
    end

    return apply!(vc, edit, String(message); normalized...)
end

function apply!(
    edit::AbstractEdit,
    message::AbstractString;
    git=:auto,
    review::Bool=true,
    require_view=nothing,
    yes::Bool=false,
    kwargs...,
)
    vc = _version_control_for_edit(edit, git)
    return _apply_with_vc!(vc, edit, message; review=review, require_view=require_view, yes=yes, kwargs...)
end

function apply!(
    edit::AbstractEdit;
    git=:auto,
    review::Bool=true,
    require_view=nothing,
    yes::Bool=false,
    kwargs...,
)
    if !(git === false || git == :none)
        error("commit message required; use apply!(patch, message) or apply!(patch; git=false)")
    end

    vc = _version_control_for_edit(edit, git)
    return _apply_with_vc!(vc, edit, nothing; review=review, require_view=require_view, yes=yes, kwargs...)
end

function apply!(
    ws::Workspace,
    edit::AbstractEdit,
    message::AbstractString;
    review::Bool=ws.review,
    require_view=nothing,
    yes::Bool=false,
    kwargs...,
)
    return _apply_with_vc!(ws.vc, edit, message; review=review, require_view=require_view, yes=yes, kwargs...)
end

function apply!(
    ws::Workspace,
    edit::AbstractEdit;
    review::Bool=ws.review,
    require_view=nothing,
    yes::Bool=false,
    kwargs...,
)
    ws.git && error("commit message required; use apply!(workspace, patch, message)")
    return _apply_with_vc!(ws.vc, edit, nothing; review=review, require_view=require_view, yes=yes, kwargs...)
end

commit!(edit::AbstractEdit, message::AbstractString; kwargs...) =
    apply!(edit, message; git=:required, kwargs...)

function commit!(ws::Workspace, edit::AbstractEdit, message::AbstractString; kwargs...)
    ws.git || error("workspace is not git-backed")
    return apply!(ws, edit, message; kwargs...)
end
