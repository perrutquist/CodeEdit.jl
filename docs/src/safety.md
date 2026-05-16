```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
end
```

# Safety and version control

CodeEdit.jl separates planning from application. Constructing an edit value does not touch the filesystem; applying an edit does.

Displaying an edit shows the planned change. Applying the edit replans it, checks that the result is still valid, writes files, and, in the standard workflow, records the change as a git commit.

## Planning before applying

An edit such as [`Replace`](@ref), [`InsertBefore`](@ref), or [`Delete`](@ref) describes an intended change. It can be inspected before it is applied:

```jldoctest safety
julia> handle = Handle("examples/safety.jl", 1)
# examples/safety.jl 1 - 1:
const SAFETY_VALUE = 1

julia> new_source = replace(string(handle), "1" => "2")
"const SAFETY_VALUE = 2\n"

julia> edit = Replace(handle, new_source)
Edit modifies examples/safety.jl:
1c1
< const SAFETY_VALUE = 1
---
> const SAFETY_VALUE = 2
```

When `require_view=true`, CodeEdit.jl stores the exact plan that was displayed. Later, [`apply!`](@ref) plans the edit again and refuses to apply it if the current plan differs from the displayed plan.

This protects against applying a stale edit after the surrounding file has changed.

## Git-backed editing

The standard workflow uses [`VersionControl`](@ref):

```jldoctest safety
julia> repo = VersionControl("examples"; require_view=true);

julia> handle = Handle("examples/safety.jl", 1);

julia> edit = Replace(handle, replace(string(handle), "1" => "2"))
Edit modifies examples/safety.jl:
1c1
< const SAFETY_VALUE = 1
---
> const SAFETY_VALUE = 2

julia> apply!(repo, edit, "Update safety example")
[main 8652943] Update safety example
 1 file changed, 1 insertion(+), 1 deletion(-)
Applied: 1 file changed, commit 8652943
```

A git-backed apply writes the edited files, stages the affected paths, and creates a commit. By default, CodeEdit.jl expects edited files to be tracked by git and rejects creation outside the worktree.

Git is the recommended undo and recovery mechanism. CodeEdit.jl does not provide an undo stack.

## Dirty files

CodeEdit.jl can reject edits when relevant tracked files are dirty. It can also make a precommit before formatting or applying the edit when `precommit_message` is supplied.

This supports two common workflows:

- keep the worktree clean before each edit;
- deliberately checkpoint existing dirty work before CodeEdit.jl changes anything.

## Applying without version control

For scratch files, generated files, or temporary changes, use [`NoVersionControl`](@ref):

```jldoctest safety
julia> write("scratch-safety.txt", "temporary = false\n");

julia> handle = Handle("scratch-safety.txt", 1; parse_as=:text);

julia> edit = Replace(handle, "temporary = true\n")
Edit modifies scratch-safety.txt:
1c1
< temporary = false
---
> temporary = true

julia> apply!(NoVersionControl(require_view=true), edit)
Applied: 1 file changed
```

This mode is explicit by design: the call site states that the edit will not be recorded as a git commit.

## Validation

Julia files are reparsed before edits are applied. If the final result would introduce syntax errors, the edit is rejected.

Combined edits are planned and validated as a unit, so intermediate states may be invalid as long as the final result is valid.

## Combined edits and filesystem failures

[`Combine`](@ref) lets several edits be planned together. Planning and validation are all-or-nothing.

Applying a combined edit that touches multiple files is still best-effort at the filesystem level. If an early file operation succeeds and a later one fails, the filesystem can be left partially changed.

Use git-backed editing for changes that matter, so the result can be reviewed and recovered.

## Limitations

CodeEdit.jl is deliberately conservative, but it is not a transactional filesystem and is not a replacement for version control.

In particular:

- multi-file applies are not atomic at the filesystem level;
- no built-in undo stack is provided;
- handles can become invalid when their referenced blocks are deleted or can no longer be matched;
- no-version-control edits are not committed unless you commit them yourself.

The safest workflow is to work in a git repository, require review for edits that matter, and keep each change small.
