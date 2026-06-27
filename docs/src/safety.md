```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    if !@isdefined(_safety_examples_ready)
        ensure_examples!()
        _safety_examples_ready = true
    end
end
```

# Safety and version control

CodeEdit.jl separates planning from application. Constructing a patch describes a change; applying a patch writes it to the filesystem.

Displaying a patch shows the planned diff. Applying the patch replans it, checks that the final result is valid, writes files, and, in the usual workflow, records the change as a git commit.

## Planning before applying

A patch such as [`replace`](@ref), [`insert_before`](@ref), or [`delete`](@ref) describes an intended change. It can be inspected before it is applied:

```jldoctest safety
julia> ensure_examples!();

julia> b = block("examples/DemoPackage.jl:5")
# examples/DemoPackage.jl 5 - 5:
const DEFAULT_LIMIT = 10

julia> p = replace(b, "10" => "20")
Patch modifies examples/DemoPackage.jl:
5c5
< const DEFAULT_LIMIT = 10
---
> const DEFAULT_LIMIT = 20
```

When `review=true`, CodeEdit.jl stores the exact plan that was displayed. Later, [`apply!`](@ref) plans the patch again and refuses to apply it if the current plan differs from the reviewed plan.

This protects against applying a stale patch after the surrounding file has changed.

For example, this patch is displayed against the original file, but the file is changed before `apply!` runs:

```jldoctest safety
julia> write("scratch.txt", "status = old\n");

julia> b = block("scratch.txt:1"; as=:text);

julia> p = replace(b, "old" => "new")
Patch modifies scratch.txt:
1c1
< status = old
---
> status = new

julia> write("scratch.txt", "status = changed elsewhere\n");

julia> apply!(p; git=false)
ERROR: patch no longer matches current files

The file changed since this patch was displayed.

Review the current patch again:

 display(p)

or rebuild it from fresh blocks:

 b = block("scratch.txt:1"; as=:text)
```

Display the patch again to review the current plan before applying it.

## Git-backed application

The standard workflow starts with a workspace inside a git worktree:

```jldoctest safety
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> b = block("examples/DemoPackage.jl:5");

julia> p = replace(b, "10" => "20")
Patch modifies examples/DemoPackage.jl:
5c5
< const DEFAULT_LIMIT = 10
---
> const DEFAULT_LIMIT = 20

julia> apply!(p, "Update default limit")
Applied: 1 file changed, commit 0000000
```

A git-backed apply writes the edited files, stages the affected paths, and creates a commit. By default, CodeEdit.jl expects edited files to live inside a git worktree unless you explicitly pass `git=false`.

Git is the recommended undo and recovery mechanism for CodeEdit.jl patches.

## Dirty files

CodeEdit.jl can reject patches when relevant tracked files are dirty. This prevents a patch from accidentally mixing with unrelated uncommitted work in the same files.

If you deliberately want to checkpoint existing dirty work first, supply `precommit`. CodeEdit.jl can then commit the existing changes before applying the new patch. If you really do want to mix changes, use `dirty=:allow`.

The important rule is to make the state of the worktree intentional before applying a patch. Do not rely on CodeEdit.jl as an undo stack; use git history for review and recovery.

## Applying without git

For scratch files, generated files, or temporary changes, pass `git=false`:

```jldoctest safety
julia> write("scratch.txt", "temporary = false\n");

julia> b = block("scratch.txt:1"; as=:text);

julia> p = replace(b, "false" => "true")
Patch modifies scratch.txt:
1c1
< temporary = false
---
> temporary = true

julia> apply!(p; git=false)
Applied: 1 file changed
```

If a path is outside git and you omit `git=false`, the error explains how to proceed:

```jldoctest safety
julia> write("scratch.txt", "temporary = false\n");

julia> b = block("scratch.txt:1"; as=:text);

julia> p = replace(b, "false" => "true");

julia> apply!(p)
ERROR: scratch.txt is not inside a git worktree

To write without committing, use:

 apply!(patch; git=false)

To create a workspace that allows non-git edits, use:

 ws = workspace("."; git=false)
```

## Validation

Julia files are reparsed before patches are applied. If the final result would introduce syntax errors, the patch is rejected before invalid source is written:

```jldoctest safety
julia> write("scratch.jl", "function ok()\n return 1\nend\n");

julia> b = block("scratch.jl:1");

julia> p = replace(b, "function broken(\n")
Patch modifies scratch.jl:
1,3c1
< function ok()
< return 1
< end
---
> function broken(

Validation errors:
- scratch.jl has a Julia syntax error

julia> apply!(p; git=false)
ERROR: patch is invalid and was not applied
```

Combined patches are planned and validated as a unit, so intermediate states may be invalid as long as the final result is valid.

## Combined patches and filesystem failures

[`patch`](@ref) and `+` let several changes be planned together. Planning and validation are all-or-nothing.

Applying a combined patch that touches multiple files is still best-effort at the filesystem level. If an early file operation succeeds and a later one fails, the filesystem can be left partially changed.

Use git-backed application for source changes you want to review, commit, or recover.

## Limitations

CodeEdit.jl rejects patches when it cannot replan or validate them safely. Use git for history, review, and recovery.

In particular:

- multi-file applies are not atomic at the filesystem level;
- no built-in undo stack is provided;
- blocks can become invalid when their referenced source is deleted or can no longer be matched;
- non-git applies are not committed unless you commit them yourself.

The safest workflow is to work in a git repository, require review for patches that matter, and keep each change small.
