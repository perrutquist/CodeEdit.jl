# CodeEdit.jl
[![CI](https://github.com/perrutquist/CodeEdit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/perrutquist/CodeEdit.jl/actions/workflows/CI.yml)
[![Documentation](https://github.com/perrutquist/CodeEdit.jl/actions/workflows/Documentation.yml/badge.svg)](https://github.com/perrutquist/CodeEdit.jl/actions/workflows/Documentation.yml)
[![Dev docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://perrutquist.github.io/CodeEdit.jl/dev/)
[![Stable docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://perrutquist.github.io/CodeEdit.jl/stable/)

CodeEdit.jl is a Julia package for making small, reviewable source edits from the Julia command line. Instead of manipulating raw line ranges, you work with handles to parsed source blocks, build edit objects, inspect the planned diff, and apply the change through git or an explicit no-version-control mode.

It is designed for workflows where source changes should be easy to review, easy to commit, and safe to apply incrementally.

## Why CodeEdit?

CodeEdit.jl is useful when you want to:

- locate the function, type, constant, or text paragraph that contains a source location;
- inspect that block directly at the REPL;
- build edits as Julia values before touching the filesystem;
- require a reviewed diff before applying a change;
- record normal source edits as git commits;
- update loaded definitions with Revise.jl when Revise is available.

## Quick example

Suppose `foo.jl` contains this function:

```julia
function foo(x)
    x + 1
end
```

Create a handle to the block containing line 2:

```julia-repl
julia> h = Handle("foo.jl", 2)
# foo.jl 1 - 3:
function foo(x)
    x + 1
end
```

Because line 2 is inside the function, the handle points to the whole function block.

Now build an edit and review the planned diff:

```julia-repl
julia> edit = Replace(h, replace(string(h), "x + 1" => "x + 2"))
Edit modifies foo.jl:
2c2
<     x + 1
---
>     x + 2
```

Apply the edit through git:

```julia-repl
julia> repo = VersionControl("."; require_view=true)
GitVersionControl("."; require_view=true)

julia> apply!(repo, edit, "Change foo increment")
Applied: 1 file changed, commit a1b2c3d
```

Constructing an edit does not modify files. Applying it through `VersionControl` writes the change, stages the affected paths, commits the result, and returns an `ApplyResult` with the affected files, commit information, and applied diff text.

For scratch files, generated files, or other changes that should not create a commit, use an explicit no-version-control specification:

```julia-repl
julia> write("scratch.txt", "status = old\n")
11

julia> h = Handle("scratch.txt", 1; parse_as=:text)
# scratch.txt 1 - 1:
status = old

julia> edit = Replace(h, "status = new\n")
Edit modifies scratch.txt:
1c1
< status = old
---
> status = new

julia> apply!(NoVersionControl(require_view=true), edit)
Applied: 1 file changed
```

If **Revise.jl** is loaded, CodeEdit.jl calls `Revise.revise()` after each successful edit so changed method definitions usually take effect immediately.

## Core ideas

The basic workflow is:

```text
Handle -> Edit -> Displayed plan -> Apply -> Commit
```

- A [`Handle`](@ref) points to one parsed block of source or text.
- An edit such as `Replace`, `InsertBefore`, or `Delete` describes an intended change.
- Displaying or stringifying an edit shows the exact plan.
- With `require_view=true`, `apply!` checks that the plan has not changed before writing files.
- Git-backed edits stage affected paths and create a commit.

## Safety at a glance

CodeEdit.jl separates planning from applying. It reparses Julia files before applying edits, can require affected files to be versioned, can reject dirty files, and can require that the exact displayed plan is still current.

For details, see the manual sections on editing and safety.

## Manual

The README is only a short introduction. The full documentation is organized as a guide:

- [Getting started](https://perrutquist.github.io/CodeEdit.jl/dev/getting-started/): make a first reviewed edit.
- [Blocks and handles](https://perrutquist.github.io/CodeEdit.jl/dev/concepts/): understand how CodeEdit.jl sees source files.
- [Editing code](https://perrutquist.github.io/CodeEdit.jl/dev/editing/): replace, insert, delete, combine, and apply edits.
- [Safety and version control](https://perrutquist.github.io/CodeEdit.jl/dev/safety/): understand review checks, git integration, and failure modes.
- [Finding errors from stacktraces](https://perrutquist.github.io/CodeEdit.jl/dev/searching-errors/): locate code from captured stacktraces.
- [API reference](https://perrutquist.github.io/CodeEdit.jl/dev/api/): look up exported names.

## Getting block handles

`Handle(path, line, [pos=1])` - Returns a handle to the block containing the character at line `line`, character position `pos`. If that location is not inside a block, returns the next block after that location. If the location is outside the file's valid line or character bounds, throws an `ArgumentError`.

`Handle(method)` - Returns a handle to a method, when source information is available. For example, `Handle.(methods(f))` returns handles to methods of `f`.

`eof_handle(path)` - Returns a handle to the end of the file. (Useful for inserting code before.)

`handles(path)` / `handles(paths)` / `handles(root, glob)` - Returns a `Set` of `Handle`s to all blocks in a file, or in a set of files (including EOF blocks). If the keyword argument `includes` is `true`, then `include` statements are followed recursively. Recursive include traversal uses cycle detection so include loops are visited at most once.

`handles(vc::VersionControl)` - Returns handles for files tracked by the git repository. Files that cannot be read as valid UTF-8 are skipped.

The functions throw an `ArgumentError` if a Julia file cannot be parsed, if a file contains invalid UTF-8, or if `Handle(path, line, pos)` is asked for a location outside the file.

Paths that currently refer to the same file are detected by comparing device and inode information. Internally, cached files are accessed via an absolute path, while handles retain the user-supplied path for display.

Handles referring to the same code block are interned: they compare as identical with `===`.

## Searching

`search(handles, needle)` - Returns a `Set` of blocks that contain `needle`. This is a convenience wrapper for `filter(h -> occursin(needle, string(h)), handles)`. `needle` may be a string or a regular expression.

`search(handles, trace)` - Returns handles to code referenced by a stacktrace or backtrace-like object, such as a backtrace from `catch_backtrace()` or a collection of stack frames. To search for an error location, pass the captured stacktrace/backtrace rather than the thrown error value.

The `search` functions also accept a file path, a vector of file paths, or a directory path and a glob pattern in place of `handles`.

## Editing

Editing is performed by first creating one or more "edit" objects (`<: AbstractEdit`) and then passing those to the `apply!` function.

`Replace(handle, new_code)` - An edit that replaces the code (or text) that `handle` refers to with `new_code`.

`Delete(handle)` - An edit which removes the code. EOF handles are unaffected.

`InsertBefore(handle, new_code)` / `InsertAfter(handle, new_code)` - Edits that insert `new_code` before/after the block that `handle` points to.

`CreateFile(path, new_code; parse_as=:auto)` - An edit which creates a new file. `parse_as` may be `:auto`, `:julia`, or `:text`.

`MoveFile(old_path, new_path)` - An edit which renames or moves a file. Source or destination symlink paths are rejected.

`DeleteFile(path)` - An edit which deletes a file. Symlink paths are rejected.

`Combine(edit1, edit2, ...)` - An edit that combines a set of other edits to be applied in the given order.  For example `Combine(InsertBefore(destination, string(source)), Delete(source))` creates an edit that will move a block of code. Within a combined edit, later child edits track the block locations produced by earlier child edits without reparsing in between, so intermediate states do not need to be syntactically valid. The affected files are reparsed and validated only after the entire combined edit has been planned. Planning and validation are all-or-nothing, but applying a multi-file combined edit is still best-effort at the filesystem level, so a later filesystem failure can still cause a partial apply.

`edit1 * edit2` - Shorthand for `Combine(edit1, edit2)`. Chaining `*` appends edits in left-to-right order.

`VersionControl(path; kwargs...)` - A git-backed version-control specification for the repository at `path`.

`GitVersionControl(path; kwargs...)` - A convenience constructor for a git-backed version-control specification.

`NoVersionControl(; kwargs...)` - An explicit specification for applying edits without version control.

`apply!(repo, edit, message)` - Apply an edit, update files on disk, stage the affected paths, and create a git commit with `message`. This is the standard workflow.

`apply!(repo, edit; default_message="...")` - Apply and commit using a default message supplied either in the call or in the `VersionControl` object.

`apply!(NoVersionControl(require_view=true), edit)` - Apply without version control, while requiring the edit to have been displayed.

`apply!(edit)` - Always errors. Pass an explicit `VersionControl` or `NoVersionControl` specification.

`apply!` returns an `ApplyResult` with `changes`, `commits`, `diff`, and `formatted_paths` fields. Its default display is brief, for example `Applied: 1 file changed` or `Applied: 2 files changed, commit a1b2c3d`.

Important `apply!` keyword arguments can be stored in `VersionControl(path; kwargs...)` or passed directly to `apply!`:

- `require_view=false` - If `true`, reject edits that have not been displayed. REPL printing, calls to `Base.display(edit)`, and calls to `string(edit)` all count.
- `require_versioning=true` for git, `false` without version control - If `true`, reject edits to existing files that are not tracked by git and reject creation outside the worktree.
- `require_clean` - If `true`, reject edits when tracked files in scope are dirty. Defaults to `true` unless `precommit_message` is supplied.
- `atomic_repo=false` - If `true`, dirty-file checks and precommits apply to the whole repository rather than only affected files.
- `precommit_message` - Commit message used to commit dirty tracked files before formatting or applying the edit.
- `formatter` - Function from `AbstractString` to `AbstractString` applied to affected files before the edit.
- `preformat=true` - If `true` and a formatter is supplied, format affected files before applying the edit.
- `format_message` - Commit message for formatter-only changes.
- `default_message` - Commit message used when `apply!(repo, edit)` is called without a positional message.

When `require_view=true`, displaying an edit records the exact plan that was shown; `apply!` replans the edit and rejects it if the plan changed. Handles automatically adapt to changing line numbers due to edits elsewhere in the file.

Applying edits can modify or invalidate the handles that they contain. An invalidated handle no longer refers to any code.

Use raw string literals, e.g. `raw"""..."""`, to avoid escaping backslashes and dollar signs when writing Julia code into a string literal.

There is no built-in undo function. The recommended workflow is to use `apply!(VersionControl("."), edit, "message")` so each edit is recorded as a git commit.

**Revise.jl** is an optional weak dependency. When Revise is loaded, CodeEdit.jl calls `Revise.revise()` after a successful `apply!`. Revise failures are reported as warnings because the filesystem edit has already been applied.

## Viewing

Code handles are prefixed by a `#` symbol and a filename and line range, then a newline before the code block itself.

A vector of code handles is displayed as an overview, except that a one-element vector displays the contained handle in full.

Invalid handles are displayed as `#invalid`.

`display(handle)` - Displays the code.

`display(handles)` - Displays an overview of a `Set` of handles, starting with the number of handles, then grouping entries by file. Handles are sorted by canonical file path and byte span, while each file header uses the path from the first handle in that file group. Each handle is shown on one line with its line range and approximately 40 characters of code.

`display(edit)` - Displays a diff of the edit, and marks it as displayed. Also displays any syntax errors that would be present in the final result of the edit. Converting an edit to a string also marks it as displayed.

## Convenience

`filepath(handle)` - Returns the path to the file that the handle refers to.

`lines(handle)` - Returns the range of lines in the file that a handle points to.

`Base.string(handle)` - Returns the block that the handle points to as a string.

`docstring(handle)` - Returns the docstring as a string (not as Julia code), or `nothing` if the block has no docstring. Docstrings are extracted by reparsing the block source when needed rather than by storing separate docstring spans.

`is_valid(handle)` - Returns true if the handle is valid, i.e. the block that it points to still exists.

`is_julia(handle)` / `is_text(handle)` - Returns whether the handle was parsed as Julia source or plain text.

`is_versioned(vc, handle)` - Returns whether the handle's file is tracked by the git repository described by `vc`. `is_versioned(vc)` returns a predicate suitable for `filter`.

`filepath_matches(handle, regex)` - Returns whether the handle's filepath matches `regex`. `filepath_matches(regex)` returns a predicate suitable for `filter`.

`is_valid(edit)` - Returns true if an edit could be applied without introducing any syntax errors in the final file contents.

`Base.occursin(handle, trace)` - Returns `true` if the code that `handle` points to occurs in the stacktrace `trace`.

## Reindexing

After files are modified outside CodeEdit.jl, existing handles may no longer match the file contents. The `reindex()` function attempts to update all handles to point to the correct block using full block spans. This may invalidate some handles and modify the contents of others.

Reindexing is triggered automatically when a cached file’s modification timestamp changes, so manual calls are usually unnecessary.


## Development note

Parts of CodeEdit.jl were developed with assistance from large language models under human review.
