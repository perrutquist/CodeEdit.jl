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

CodeEdit.jl separates planning from application. Constructing an edit value does not touch the filesystem; applying an edit does.

Displaying an edit shows the planned change. Applying the edit replans it, checks that the result is still valid, writes files, and, in the standard workflow, records the change as a git commit.

## Planning before applying

An edit such as [`Replace`](@ref), [`InsertBefore`](@ref), or [`Delete`](@ref) describes an intended change. It can be inspected before it is applied:

```jldoctest safety
julia> handle = Handle("examples/DemoPackage.jl", 5)
# examples/DemoPackage.jl 5 - 5:
const DEFAULT_LIMIT = 10

julia> new_source = replace(string(handle), "10" => "20")
"const DEFAULT_LIMIT = 20\n"

julia> edit = Replace(handle, new_source)
Edit modifies examples/DemoPackage.jl:
5c5
< const DEFAULT_LIMIT = 10
---
> const DEFAULT_LIMIT = 20
```

When `require_view=true`, CodeEdit.jl stores the exact plan that was displayed. Later, [`apply!`](@ref) plans the edit again and refuses to apply it if the current plan differs from the displayed plan.

This protects against applying a stale edit after the surrounding file has changed.

For example, this edit is displayed against the original file, but the file is changed before `apply!` runs:

```jldoctest safety
julia> write("scratch.txt", "status = old\n");

julia> handle = Handle("scratch.txt", 1; parse_as=:text);

julia> edit = Replace(handle, "status = new\n")
Edit modifies scratch.txt:
1c1
< status = old
---
> status = new

julia> write("scratch.txt", "status = changed elsewhere\n");

julia> apply!(NoVersionControl(require_view=true), edit)
ERROR: displayed edit was invalid
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:44
 [2] #compile_checked_plan#39
   @ ~/Documents/Julia/CodeEdit/src/apply.jl:472 [inlined]
 [3] compile_checked_plan
   @ ~/Documents/Julia/CodeEdit/src/apply.jl:465 [inlined]
 [4] apply!(vc::NoVersionControl{@NamedTuple{require_view::Bool}}, edit::Replace; kwargs::@Kwargs{})
   @ CodeEdit ~/Documents/Julia/CodeEdit/src/apply.jl:546
 [5] apply!(vc::NoVersionControl{@NamedTuple{require_view::Bool}}, edit::Replace)
   @ CodeEdit ~/Documents/Julia/CodeEdit/src/apply.jl:540
 [6] top-level scope
   @ none:1
```

Display the edit again to review the current plan before applying it.

## Git-backed editing

The standard workflow uses [`VersionControl`](@ref):

```jldoctest safety
julia> repo = VersionControl("examples"; require_view=true);

julia> handle = Handle("examples/DemoPackage.jl", 5);

julia> edit = Replace(handle, replace(string(handle), "10" => "20"))
Edit modifies examples/DemoPackage.jl:
5c5
< const DEFAULT_LIMIT = 10
---
> const DEFAULT_LIMIT = 20

julia> apply!(repo, edit, "Update default limit")
Applied: 1 file changed, commit 0000000
```

A git-backed apply writes the edited files, stages the affected paths, and creates a commit. By default, CodeEdit.jl expects edited files to be tracked by git and rejects creation outside the worktree.

Git is the recommended undo and recovery mechanism. CodeEdit.jl does not provide an undo stack.

## Dirty files

CodeEdit.jl can reject edits when relevant tracked files are dirty. This prevents an edit from accidentally mixing with uncommitted changes in the same files.

If you deliberately want to checkpoint existing dirty work first, supply `precommit_message`. CodeEdit.jl can then commit the existing changes before formatting or applying the new edit. This supports two workflows:

- keep the relevant files clean before each edit;
- explicitly checkpoint dirty work before CodeEdit.jl changes anything.

The important rule is to make the state of the worktree intentional before applying an edit. Do not rely on CodeEdit.jl as an undo stack; use git history for review and recovery.

## Applying without version control

For scratch files, generated files, or temporary changes, use [`NoVersionControl`](@ref):

```jldoctest safety
julia> write("scratch.txt", "temporary = false\n");

julia> handle = Handle("scratch.txt", 1; parse_as=:text);

julia> edit = Replace(handle, "temporary = true\n")
Edit modifies scratch.txt:
1c1
< temporary = false
---
> temporary = true

julia> apply!(NoVersionControl(require_view=true), edit)
Applied: 1 file changed
```

This mode is explicit by design: the call site states that the edit will not be recorded as a git commit.

## Validation

Julia files are reparsed before edits are applied. If the final result would introduce syntax errors, the edit is rejected before the invalid source is written:

```jldoctest safety
julia> write("scratch.jl", "function ok()\n    return 1\nend\n");

julia> handle = Handle("scratch.jl", 1);

julia> edit = Replace(handle, "function broken(\n")
Edit modifies scratch.jl:
1,3c1
< function ok()
<     return 1
< end
---
> function broken(
Validation errors:
- ArgumentError: Julia file could not be parsed: /Users/rutquist/Documents/Julia/CodeEdit/docs/scratch.jl

julia> apply!(NoVersionControl(require_view=true), edit)
ERROR: displayed edit was invalid
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:44
 [2] #compile_checked_plan#39
   @ ~/Documents/Julia/CodeEdit/src/apply.jl:469 [inlined]
 [3] compile_checked_plan
   @ ~/Documents/Julia/CodeEdit/src/apply.jl:465 [inlined]
 [4] apply!(vc::NoVersionControl{@NamedTuple{require_view::Bool}}, edit::Replace; kwargs::@Kwargs{})
   @ CodeEdit ~/Documents/Julia/CodeEdit/src/apply.jl:546
 [5] apply!(vc::NoVersionControl{@NamedTuple{require_view::Bool}}, edit::Replace)
   @ CodeEdit ~/Documents/Julia/CodeEdit/src/apply.jl:540
 [6] top-level scope
   @ none:1
```

Combined edits are planned and validated as a unit, so intermediate states may be invalid as long as the final result is valid.

## Combined edits and filesystem failures

[`Combine`](@ref) lets several edits be planned together. Planning and validation are all-or-nothing.

Applying a combined edit that touches multiple files is still best-effort at the filesystem level. If an early file operation succeeds and a later one fails, the filesystem can be left partially changed.

Use git-backed editing for source changes you want to review, commit, or recover.

## Limitations

CodeEdit.jl rejects edits when it cannot replan or validate them safely, but it is not a transactional filesystem and is not a replacement for version control.

In particular:

- multi-file applies are not atomic at the filesystem level;
- no built-in undo stack is provided;
- handles can become invalid when their referenced blocks are deleted or can no longer be matched;
- no-version-control edits are not committed unless you commit them yourself.

The safest workflow is to work in a git repository, require review for edits that matter, and keep each change small.
