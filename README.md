# CodeEdit.jl

CodeEdit.jl is a package for locating, viewing, and editing Julia source code from the Julia command line. It has some built-in safety measures, such as requiring edit diffs to be viewed before they can be applied, but is intended to be used in conjunction with version-control software.

## Documentation

The full documentation is built with [Documenter.jl](https://documenter.juliadocs.org/). It includes conceptual pages for blocks, handles, edit review, and safety behavior. To build it locally, run:

```shell
julia --project=docs -e 'using Pkg; Pkg.develop(Pkg.PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Then open `docs/build/index.html`.

## Example

Let's say we want to look at the code in "foo.jl" on line 2.

```julia-repl
julia> h = Handle("foo.jl", 2)
# foo.jl 1 - 3:
function foo(x)
   x + 1
end
```
Because line 2 is part of a block that spans lines 1 - 3, those lines are all displayed. A handle to this code is returned.

We can use the handle to create a code edit.
```julia-repl
julia> edit = Replace(h, replace(string(h), "x + 1" => "x + 2"))
Edit modifies foo.jl:
2c2
<    x + 1
---
>    x + 2
```

Now (after our `edit` has been displayed) we can apply it.
```julia-repl
julia> apply!(edit)
Success.
```

If **Revise.jl** is loaded, CodeEdit.jl triggers `Revise.revise()` after each successful edit so the new definition of `foo(x)` typically takes effect immediately.

## Blocks

The basis for many commands is that the code is automatically divided into *blocks*. For Julia files, blocks are top-level syntactic units such as function, type, macro, constant, assignment, import, export, and include statements, optionally with attached docstrings. Top-level expressions terminated by semicolons are treated as separate blocks where possible. Blocks never overlap.

A Julia `module` is not treated as one large block. Instead, the `module ...` line and its matching `end` line are separate blocks, while the contents are subdivided normally.

At the end of each file, there is a special EOF block.

For non-Julia files, the division into *blocks* is determined by blank lines, and a block is roughly equivalent to a paragraph of text.

Most commands interpret `.jl` files as Julia code and any other file extension as text. The keyword argument `parse_as=:julia` or `parse_as=:text` can be used to override this, but if the parsing type for a file changes then all existing handles to that file are invalidated. A cached file can only have one parse mode at a time, so changing file extension or reloading it with a different parse mode forces invalidation and reload.

Under the hood, the package keeps a cache of all files that it has already parsed into blocks.

## Getting block handles

`Handle(path, line, [pos=1])` - Returns a handle to the block containing the character at line `line`, character position `pos`. If that location is not inside a block, returns the next block after that location. If the location is outside the file's valid line or character bounds, throws an `ArgumentError`.

`Handle(method)` - Returns a handle to a method, when source information is available. For example, `Handle.(methods(f))` returns handles to methods of `f`.

`eof_handle(path)` - Returns a handle to the end of the file. (Useful for inserting code before.)

`handles(path)` / `handles(paths)` / `handles(root, glob)` - Returns a `Set` of `Handle`s to all blocks in a file, or in a set of files (including EOF blocks). If the keyword argument `includes` is `true`, then `include` statements are followed recursively. Recursive include traversal uses cycle detection so include loops are visited at most once.

The functions throw an `ArgumentError` if a Julia file cannot be parsed, if a file contains invalid UTF-8, or if `Handle(path, line, pos)` is asked for a location outside the file.

Paths that currently refer to the same file are detected by comparing device and inode information. Internally, cached files are accessed via an absolute path, while handles retain the user-supplied path for display.

Handles referring to the same code block are interned: they compare as identical  with `===`.

## Searching

`search(handles, needle)` - Returns a `Set` of blocks that contain `needle`. This is a convenience wrapper for `filter(h -> occursin(needle, string(h)), handles)`

`search(handles, trace)` / `search(handles, exception)` - Returns handles to code referenced by a stacktrace-like object, such as a backtrace from `catch_backtrace()`, a collection of stack frames, or a `CapturedException`.

The `search` functions also accept a file path, a vector of file paths, or a directory path and a glob pattern in place of `handles`.

## Editing

Editing is performed by first creating one or more "edit" objects (`<: AbstractEdit`) and then passing those to the `apply!` function.

`Replace(handle, new_code)` - An edit that replaces the code (or text) that `handle` refers to with `new_code`.

`Delete(handle)` - An edit which removes the code. EOF handles are unaffected.

`InsertBefore(handle, new_code)` / `InsertAfter(handle, new_code)` - Edits that insert `new_code` before/after the block that `handle` points to.

`CreateFile(path, new_code; parse_as=:auto)` - An edit which creates a new file. `parse_as` may be `:auto`, `:julia`, or `:text`.

`MoveFile(old_path, new_path)` - An edit which renames or moves a file. Source or destination symlink paths are rejected.

`DeleteFile(path)` -  An edit which deletes a file. Symlink paths are rejected.

`Combine(edit1, edit2, ...)` - An edit that combines a set of other edits to be applied in the given order.  For example `Combine(InsertBefore(destination, string(source)), Delete(source))` creates an edit that will move a block of code. Within a combined edit, later child edits track the block locations produced by earlier child edits without reparsing in between, so intermediate states do not need to be syntactically valid. The affected files are reparsed and validated only after the entire combined edit has been planned. Planning and validation are all-or-nothing, but applying a multi-file combined edit is still best-effort at the filesystem level, so a later filesystem failure can still cause a partial apply.

`edit1 * edit2` - Shorthand for `Combine(edit1, edit2)`. Chaining `*` appends edits in left-to-right order.

`apply!(edit)` - Apply an edit, updating files on disk.

For safety, `apply!` refuses to apply an edit unless it has previously been displayed. REPL printing, calls to `Base.display(edit)`, and calls to `string(edit)` all count. Displaying an edit records the exact plan that was shown; `apply!` replans the edit and rejects it if the plan changed. Handles automatically adapt to changing line numbers due to edits elsewhere in the file.

Applying edits can modify or invalidate the handles that they contain. An invalidated handle no longer refers to any code.

Use raw string literals, e.g. `raw"""..."""`, to avoid escaping backslashes and dollar signs when writing Julia code into a string literal.

There is no undo function. It is recommended to use **git** for version control.

**Revise.jl** is an optional weak dependency. When Revise is loaded, CodeEdit.jl calls `Revise.revise()` after a successful `apply!`. Revise failures are reported as warnings because the filesystem edit has already been applied.

## Viewing

Code handles are prefixed by a `#` symbol and a filename and line range, then a newline before the code block itself.

A vector of code handles is displayed as an overview, except that a one-element vector displays the contained handle in full.

Invalid handles are displayed as `#invalid`.

`display(handle)` - Displays the code.

`display(handles)` - Displays an overview of a `Set` of handles, starting with the number of handles, then grouping entries by file. Handles are sorted by canonical file path and byte span, while each file header uses the path from the first handle in that file group. Each handle is shown on one line with its line range and approximately 40 characters of code.

`display(edit)` - Displays a diff of the edit, and marks it as displayed. Also displays any syntax errors that would be present in the final result of the edit. Converting an edit to a string also marks it as displayed.

`displayed!(edit, true)` - Marks an edit as displayed, enabling application without actually displaying it. (Use with caution.)

## Convenience

`filepath(handle)` - Returns the path to the file that the handle refers to.

`lines(handle)` - Returns the range of lines in the file that a handle points to.

`Base.string(handle)` - Returns the block that the handle points to as a string.

`docstring(handle)` - Returns the docstring as a string (not as Julia code), or `nothing` if the block has no docstring. Docstrings are extracted by reparsing the block source when needed rather than by storing separate docstring spans.

`is_valid(handle)` - Returns true if the handle is valid, i.e. the block that it points to still exists.

`is_valid(edit)` - Returns true if an edit could be applied without introducing any syntax errors in the final file contents.

`Base.occursin(handle, trace)` - Returns `true` if the code that `handle` points to occurs in the stacktrace `trace`.

## Reindexing

After files are modified outside CodeEdit.jl, existing handles may no longer match the file contents. The `reindex()` function attempts to update all handles to point to the correct block using full block spans. This may invalidate some handles and modify the contents of others.

Reindexing is triggered automatically when a cached file’s modification timestamp changes, so manual calls are usually unnecessary.
