# Blocks and handles

CodeEdit.jl works by splitting files into source or text *blocks* and returning stable references to those blocks. These handles can then be used to build edits that are applied through git or through an explicit no-version-control specification.

## Blocks

For Julia files, blocks are top-level syntactic units such as functions, types, macros, constants, assignments, imports, exports, and includes. Attached docstrings are kept with the following block.

A Julia `module` is not treated as one large block. Instead, the `module ...` line and its matching `end` line are separate blocks, while the module contents are subdivided normally.

At the end of each file, CodeEdit.jl also creates a special EOF block. EOF handles are useful when inserting code at the end of a file.

For non-Julia files, blocks are split like paragraphs using blank lines.

## Handles

A [`Handle`](@ref) points to one parsed block.

```@repl concepts
using CodeEdit

rm("examples"; recursive=true, force=true)
mkpath("examples")

write("examples/concepts.jl", """
function foo(x)
    return x + 1
end

function bar(x)
    return foo(x)
end
""")

h = Handle("examples/concepts.jl", 2)
```

Because line 2 is inside `foo`, the handle points to the whole `foo` block.

Handles are interned for a parsed file: requesting the same block again returns the same handle object.

```@repl concepts
h === Handle("examples/concepts.jl", 1)
```

## Julia and text parsing

By default, `.jl` files are parsed as Julia source and other files are parsed as text. Use `parse_as=:julia` or `parse_as=:text` to override this when constructing handles or collecting handles.

```@repl concepts
write("examples/notes.txt", """
First paragraph.

Second paragraph.
""")

handles("examples/notes.txt"; parse_as=:text)
```

A cached file has one parse mode at a time. Reloading the same file with a different parse mode invalidates existing handles for that file.

## Handle validity

Edits can update handles when their referenced block can still be matched after the edit. Handles are invalidated when their block is deleted or can no longer be matched unambiguously.

Use [`is_valid`](@ref) to check whether a handle still points to a valid block.

```@repl concepts
is_valid(h)
```

Files modified outside CodeEdit.jl are reparsed automatically when a cached timestamp changes. You can also call [`reindex`](@ref) to update cached handles explicitly.
