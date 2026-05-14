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

function git_tracked_paths(repo_root::AbstractString)
    output = git_read(repo_root, String["ls-files", "-z"])
    return String[absolute_path(joinpath(repo_root, String(rel))) for rel in split(output, '\0'; keepempty=false)]
end

function is_valid_utf8_file(path::AbstractString)
    try
        read(path, String)
        return true
    catch
        return false
    end
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
Return whether a handle's file is tracked by the given version-control
specification.
"""
function is_versioned(vc::VersionControl{:git}, handle::Handle)
    is_valid(handle) || return false

    try
        repo_root = git_worktree_root(vc.repo_path)
        return is_tracked(repo_root, filepath(handle))
    catch
        return false
    end
end

function is_versioned(::VersionControl{:none}, ::Handle)
    return false
end

is_versioned(vc::VersionControl) = Base.Fix1(is_versioned, vc)

function handles(vc::VersionControl{:git}; includes::Bool=false, parse_as::Symbol=:auto)
    repo_root = git_worktree_root(vc.repo_path)
    result = Set{Handle}()

    for path in git_tracked_paths(repo_root)
        is_valid_utf8_file(path) || continue
        union!(result, handles(path; includes=includes, parse_as=parse_as))
    end

    return result
end

function handles(::VersionControl{:none}; includes::Bool=false, parse_as::Symbol=:auto)
    return Set{Handle}()
end
