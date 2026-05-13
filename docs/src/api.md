# API reference

This page summarizes the public API exported by CodeEdit.jl.

## Handles

- [`Handle`](@ref): create a handle to the block containing a file location or method.
- [`eof_handle`](@ref): create a handle to the end of a file.
- [`handles`](@ref): collect handles for blocks in files.
- [`reindex`](@ref): update existing handles after files changed outside CodeEdit.jl.

## Searching

- [`search`](@ref): search handles, files, stacktraces, or exceptions.

## Edits

- [`AbstractEdit`](@ref): abstract supertype for edit values.
- [`Replace`](@ref): replace a block.
- [`Delete`](@ref): delete a block.
- [`InsertBefore`](@ref): insert code before a block.
- [`InsertAfter`](@ref): insert code after a block.
- [`CreateFile`](@ref): create a new file.
- [`MoveFile`](@ref): move or rename a file.
- [`DeleteFile`](@ref): delete a file.
- [`Combine`](@ref): combine edits into one planned edit.
- [`apply!`](@ref): apply an edit through an explicit version-control specification.
- [`displayed!`](@ref): mark an edit as displayed.

The `edit1 * edit2` operator is shorthand for `Combine(edit1, edit2)`. Chaining `*` appends edits to a combined edit.

Combined edits are planned and validated as a unit, but applying a combined edit that touches multiple files is best-effort at the filesystem level and can partially apply if a later filesystem operation fails.

## Version control

- [`VersionControl`](@ref): describe a git repository and default `apply!` keyword arguments.
- [`GitVersionControl`](@ref): convenience constructor for git-backed editing.
- [`NoVersionControl`](@ref): explicitly apply edits without version control.
- [`ApplyResult`](@ref): successful result returned by `apply!`.

`apply!(repo, edit, message)` applies an edit, stages affected paths, and creates a git commit with `message`.

`apply!(repo, edit; default_message="...")` uses a default commit message supplied either in the call or in the `VersionControl` object.

`apply!(NoVersionControl(require_view=true), edit)` applies without git while still requiring a displayed review.

Display, printing, and `string(edit)` store the exact plan that was shown. When `require_view=true`, [`apply!`](@ref) replans the edit and rejects it if the current plan differs from the displayed plan.

## Convenience functions

- [`filepath`](@ref): return the file path for a handle.
- [`lines`](@ref): return the line range for a handle.
- [`docstring`](@ref): extract an attached docstring.
- [`is_valid`](@ref): test whether a handle or edit is valid.
- `string(handle)`: return the block text for a handle.
- `string(edit)`: return the displayed edit plan and mark the edit as displayed.
- `display(handle)`: show a handle header and source block.
- `display(edit)`: show the edit plan and mark the edit as displayed.
- `occursin(handle, trace)`: test whether a handle's source location occurs in a stacktrace-like object.

## Exported names

```@docs
Handle
eof_handle
handles
reindex
search
AbstractEdit
Replace
Delete
InsertBefore
InsertAfter
CreateFile
MoveFile
DeleteFile
Combine
apply!
displayed!
ApplyResult
VersionControl
GitVersionControl
NoVersionControl
filepath
lines
docstring
is_valid
```
