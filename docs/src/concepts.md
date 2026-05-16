```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
end
```

# Blocks and handles

CodeEdit.jl edits files by first splitting them into source or text *blocks*. A [`Handle`](@ref) is a stable reference to one such block and is the object passed to search and edit operations.

Edits built from handles can be applied through git or through an explicit no-version-control specification.

## Blocks

For Julia files, blocks are top-level syntactic units such as functions, types, macros, constants, assignments, imports, exports, and includes. Attached docstrings are kept with the block they document.

For example, CodeEdit.jl sees a file like this as several separate blocks:

```julia
module Inventory              # block

const DEFAULT_TAX = 0.25       # block

function price_with_tax(x)     # block
    return x * (1 + DEFAULT_TAX)
end

end                           # block
                              # EOF block
```

A Julia `module` is not treated as one large block. The `module ...` line and its matching `end` line are separate blocks, while the module body is subdivided normally.

At the end of each file, CodeEdit.jl creates a special EOF block. EOF handles are useful when inserting code at the end of a file.

For non-Julia files, blocks are paragraphs separated by blank lines.

## Handles

A [`Handle`](@ref) points to one parsed block. It is the object passed to search, display, and edit operations.

```jldoctest concepts
julia> h = Handle("examples/concepts.jl", 2)
# examples/concepts.jl 1 - 3:
function foo(x)
    return x + 1
end
```

Because line 2 is inside `foo`, the handle refers to the whole `foo` block.

Handles are interned for a parsed file: requesting the same block again returns the same handle object.

```jldoctest concepts
julia> h === Handle("examples/concepts.jl", 1)
true
```

## Julia and text parsing

By default, `.jl` files are parsed as Julia source and other files are parsed as text. Use `parse_as=:julia` or `parse_as=:text` to override this behavior when constructing or collecting handles.

```jldoctest concepts
julia> handles("examples/concepts-notes.txt"; parse_as=:text)
3 handles
# examples/concepts-notes.txt:
  1 - 1: First paragraph.
  3 - 3: Second paragraph.
  EOF:
```

A cached file has one parse mode at a time. Reloading the same file with a different parse mode invalidates existing handles for that file.

## Handle validity

Edits update handles when their referenced block can still be matched after the edit. Handles are invalidated when their block is deleted or can no longer be matched unambiguously.

Use [`is_valid`](@ref) to test whether a handle still refers to a valid block.

```jldoctest concepts
julia> is_valid(h)
true
```

Files modified outside CodeEdit.jl are reparsed automatically when a cached timestamp changes. Call [`reindex`](@ref) to update cached handles explicitly.
