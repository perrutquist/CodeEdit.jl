# API reference

This page summarizes the exported API. See the manual for task-oriented examples.

## Handles

Handles identify source or text blocks.

- [`Handle`](@ref): create a handle to the block containing a file location or method.
- [`eof_handle`](@ref): create a handle to the end of a file.
- [`handles`](@ref): collect handles for blocks in files.
- [`reindex`](@ref): update existing handles after files changed outside CodeEdit.

## Searching

- [`search`](@ref): search handles, files, stacktraces, or exceptions.

## Edits

Edits describe changes without applying them.

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

The `edit1 * edit2` operator is shorthand for `Combine(edit1, edit2)`. Chaining `*` appends edits in left-to-right order.

Combined edits are planned and validated as a unit. Intermediate states may be invalid Julia syntax if the final result is valid.

## Version control

Version-control specifications make the application policy explicit.

- [`VersionControl`](@ref): describe a git repository and default `apply!` keyword arguments.
- [`GitVersionControl`](@ref): convenience constructor for git-backed editing.
- [`NoVersionControl`](@ref): explicitly apply edits without version control.

Common apply forms:

```julia
apply!(repo, edit, "Commit message")
apply!(repo, edit; default_message="Commit message")
apply!(NoVersionControl(require_view=true), edit)
```

`apply!(repo, edit, message)` applies an edit, stages affected paths, and creates a git commit with `message`.

`apply!(NoVersionControl(require_view=true), edit)` applies without git while still requiring a displayed review.

When `require_view=true`, display, printing, and `string(edit)` store the exact plan that was shown. [`apply!`](@ref) replans the edit and rejects it if the current plan differs from the displayed plan.

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

Additional exported helpers include:

- `is_julia(handle)` and `is_text(handle)`: inspect the parse mode of a handle.
- `is_versioned(handle, vc)` and `is_versioned(vc)`: test whether a handle's file is tracked by a git repository.
- `filepath_matches(handle, regex)` and `filepath_matches(regex)`: filter handles by displayed path.

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
VersionControl
GitVersionControl
NoVersionControl
filepath
lines
docstring
is_valid
is_julia
is_text
is_versioned
filepath_matches
```
