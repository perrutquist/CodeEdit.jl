# API reference

This page summarizes the public API exported by CodeEdit.jl. For task-oriented examples, see [Getting started](getting-started.md), [Searching source](searching.md), and [Editing code](editing.md).

Most workflows start by collecting [`Handle`](@ref)s, selecting the blocks to edit, constructing one or more [`AbstractEdit`](@ref) values, displaying the planned diff, and applying it through an explicit version-control policy.

## Handles and source blocks

Handles are stable references to parsed source or text blocks. They can be created from files, methods, stack frames, repositories, and search results.

```@docs
Handle
handles
handle_at
eof_handle
reindex
```

## Searching and filtering

Search functions return `Set{Handle}` values. Use ordinary set operations such as `union`, `intersect`, and `setdiff` to combine selections.

```@docs
search
filepath_matches
is_julia
is_text
is_versioned
```

## Edits

Edits are immutable descriptions of intended changes. Constructing an edit does not modify the filesystem. Displaying or stringifying an edit shows the planned diff and records the displayed plan for optional review enforcement.

```@docs
AbstractEdit
Replace
Delete
InsertBefore
InsertAfter
CreateFile
MoveFile
DeleteFile
Combine
displayed!
```

## Applying edits and version control

Edits are applied through an explicit [`VersionControl`](@ref) specification. Git-backed application can check cleanliness, require files to be versioned, stage affected paths, and create commits. [`NoVersionControl`](@ref) is available for scratch files and generated output.

```@docs
VersionControl
GitVersionControl
NoVersionControl
apply!
```

Calling `Base.arg_gen(repo)` when `repo <: GitVersionControl` returns the repository path, so that `repo` can be interpolated into a `Cmd` command, e.g. ```run(`git -C $repo status`)```.

## Handle utilities

These convenience functions inspect handles and validate handles or edits.

```@docs
filepath
lines
docstring
is_valid
```

Calling `string(handle)` returns the source text for a handle. `string(edit)` and `display(edit)` show the planned diff and mark that exact plan as displayed.
