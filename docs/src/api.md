# API reference

This page summarizes the public high-level API exported by CodeEdit.jl. For task-oriented examples, see [Getting started](getting-started.md), [Searching source](searching.md), and [Editing code](editing.md).

Most workflows start by opening a [`Workspace`](@ref), selecting one or more [`Block`](@ref)s, constructing a [`Patch`](@ref), displaying the planned diff, and applying it.

## Workspaces

A workspace represents the root directory being edited.

```@docs
Workspace
workspace
repo
project
codebase
```

## Blocks and source

Blocks are user-facing source objects. They can be selected from files, methods, stack frames, workspaces, and stacktraces.

```@docs
Block
block
blocks
source
text
path
lines
span
docstring
docs
reindex
is_valid
```

## Searching

Search functions return block collections. Use ordinary set operations such as `union`, `intersect`, and `setdiff` when working with set-like results.

```@docs
find
search
grep
where
filepath_matches
is_julia
is_text
is_versioned
```

## Patches

Patches are immutable descriptions of intended changes. Constructing a patch does not modify the filesystem. Displaying or stringifying a patch shows the planned diff and records the reviewed plan when review is enabled.

```@docs
Patch
replace
delete
insert_before
insert_after
append_to
prepend_to
create_file
move_file
delete_file
patch
preview
diff
rename
```

## Applying patches

Patches are applied with [`apply!`](@ref) or [`commit!`](@ref). Git-backed application can check cleanliness, infer worktrees, stage affected paths, and create commits. Non-git writes are enabled explicitly with `git=false`.

```@docs
apply!
commit!
```

Calling `String(block)` returns the source text for a block. `String(patch)` and `display(patch)` show the planned diff and mark that exact plan as reviewed.
