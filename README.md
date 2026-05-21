# CodeEdit.jl
[![CI](https://github.com/perrutquist/CodeEdit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/perrutquist/CodeEdit.jl/actions/workflows/CI.yml)
[![Documentation](https://github.com/perrutquist/CodeEdit.jl/actions/workflows/Documentation.yml/badge.svg)](https://github.com/perrutquist/CodeEdit.jl/actions/workflows/Documentation.yml)
[![Dev docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://perrutquist.github.io/CodeEdit.jl/dev/)
[![Stable docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://perrutquist.github.io/CodeEdit.jl/stable/)

CodeEdit.jl is a Julia package for inspecting and editing source code from Julia. It represents source blocks with handles, so edits can be planned, reviewed, and applied without manually writing diffs.

It is designed for workflows where source changes are made programmatically or interactively, with optional git integration for recording applied edits.

## When it is useful

CodeEdit.jl may be useful when you want to:

- find and inspect relevant code blocks from Julia
- write Julia code that edits Julia source
- review planned changes before they touch the filesystem
- optionally record each applied edit as a git commit

## Quick example

Suppose `foo.jl` contains this function:

```julia
function foo(x)
    x + 1
end
```

Create a handle to the block containing the function:

```julia-repl
julia> h = only(search("foo.jl", "function foo"))
# foo.jl 1 - 3:
function foo(x)
    x + 1
end
```

Now build an edit and review the planned diff:

```julia-repl
julia> edit = Replace(h, replace(string(h), "x + 1" => "x + 2"))
Edit modifies foo.jl:
2c2
<     x + 1
---
>     x + 2
```

Displaying the edit shows the planned diff but does not modify the file.

Now, apply the edit through git:

```julia-repl
julia> repo = VersionControl("."; require_view=true)
GitVersionControl("."; require_view=true)

julia> apply!(repo, edit, "Change foo increment")
Applied: 1 file changed, commit a1b2c3d
```

For scratch files, generated files, or other changes that should not create a commit, use `NoVersionControl()` instead of a `VersionControl` object.

If **Revise.jl** is loaded, CodeEdit.jl calls `Revise.revise()` after each successful edit so changed method definitions usually take effect immediately.

## Core ideas

The basic workflow is:

```text
Handle -> Edit -> Displayed plan -> Apply -> Commit
```

- A `Handle` points to one parsed block of source or text.
- An edit such as `Replace`, `InsertBefore`, or `Delete` describes an intended change.
- Displaying or stringifying an edit shows the exact planned diff.
- With `require_view=true`, `apply!` checks that the displayed plan is still current before writing files.
- Git-backed edits stage affected paths and create a commit.

## Safety

CodeEdit.jl separates planning from applying. Edits are ordinary Julia values until they are passed to `apply!`.

Depending on the version-control settings, applying an edit can require that:

- the planned diff has already been displayed
- affected files are tracked by git
- affected files are clean before editing
- the final edited Julia files parse successfully

Git-backed edits stage affected files and create a commit.

## Manual

The README is a short introduction. The full documentation is organized as a guide:

- [Getting started](https://perrutquist.github.io/CodeEdit.jl/dev/getting-started/): make a first reviewed edit.
- [Blocks and handles](https://perrutquist.github.io/CodeEdit.jl/dev/concepts/): understand how CodeEdit.jl sees source files.
- [Searching source](https://perrutquist.github.io/CodeEdit.jl/dev/searching/): find blocks by text, regular expression, path, and line number.
- [Editing code](https://perrutquist.github.io/CodeEdit.jl/dev/editing/): replace, insert, delete, combine, and apply edits.
- [Safety and version control](https://perrutquist.github.io/CodeEdit.jl/dev/safety/): understand review checks, git integration, and failure modes.
- [Finding errors from stacktraces](https://perrutquist.github.io/CodeEdit.jl/dev/searching-errors/): locate code from captured stacktraces.
- [API reference](https://perrutquist.github.io/CodeEdit.jl/dev/api/): look up exported names.

## What you can do

CodeEdit.jl works with handles to parsed source blocks. With those handles you can:

- inspect functions, methods, modules, and other top-level blocks
- search source blocks by string or regular expression
- replace, delete, move, or insert code
- create, move, or delete files
- apply edits through git or explicitly without version control
- require that an edit has been displayed before it is applied

For scratch files, generated files, or other changes that should not create a commit, use `NoVersionControl()` instead of a `VersionControl` object.

If **Revise.jl** is loaded, CodeEdit.jl calls `Revise.revise()` after each successful edit so changed method definitions usually take effect immediately.

## AI-assisted workflows

CodeEdit.jl is also intended to be useful in AI-assisted coding workflows. Handles make it possible to find and edit relevant source blocks without loading entire files into context, and displayed edit plans make small reviewed changes easier to apply precisely.

## Development note

CodeEdit.jl has been developed with assistance from large language models. Much of the code and documentation was drafted with AI help, then reviewed, tested, and revised by the maintainer.
