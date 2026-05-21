```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    if !@isdefined(_concepts_examples_ready)
        ensure_examples!()
        _concepts_examples_ready = true
    end
end
```

# Blocks and handles

CodeEdit.jl edits files by first splitting them into source or text *blocks*. A [`Handle`](@ref) is a stable reference to one such block and is the object passed to search and edit operations.

Edits built from handles can be applied through git or through an explicit no-version-control specification.

## Blocks

For Julia files, blocks are top-level syntactic units such as functions, types, macros, constants, assignments, imports, exports, and includes. Attached docstrings stay with the block they document, so replacing a documented function keeps the docstring and function together. Use [`docstring`](@ref) to inspect the docstring attached to a handle.

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

A Julia `module` is split into separate blocks. The `module ...` line and its matching `end` line are separate blocks, while the module body is subdivided normally. Single-line modules are kept as one block. Modules where the beginning or end include more code on the same line, such as `module M; x = 1` or `y = 2; end # module`, also become one single block; avoid this syntax when you want the module body to be editable as separate blocks.

At the end of each file, CodeEdit.jl creates a special EOF block. EOF handles are useful when inserting code at the end of a file.

For non-Julia files, blocks are paragraphs separated by blank lines.

## Handles

A [`Handle`](@ref) points to one parsed block. It is the object passed to search, display, and edit operations.

```jldoctest concepts
julia> h = Handle("examples/DemoPackage.jl", 14)
# examples/DemoPackage.jl 13 - 15:
function increment(x)
    return x + 1
end
```

Because line 14 is inside `increment`, the handle refers to the whole `increment` block.

Handles are interned for a parsed file: requesting the same block again returns the same handle object.

```jldoctest concepts
julia> h === Handle("examples/DemoPackage.jl", 13)
true
```

## Handle collections

[`handles`](@ref) and [`search`](@ref) return sets of handles. A handle appears at most once in a set, so standard set operations are useful for combining and narrowing selections:

```julia
repo = VersionControl("examples")
hs = handles(repo)

definitions = search(hs, "function")
limits = search(hs, "DEFAULT_LIMIT")
targets = union(definitions, limits)
```

Set iteration order is arbitrary. The displayed summary is sorted for readability. Use `sort!(collect(hs))` when order matters.

Use a vector when order has meaning. For example, `Handle.(stacktrace)` preserves stacktrace order, which is useful when inspecting errors.

## Julia and text parsing

By default, `.jl` files are parsed as Julia source and other files are parsed as text. Use `parse_as=:julia` or `parse_as=:text` to override this behavior when constructing or collecting handles.

```jldoctest concepts
julia> handles("examples/notes.txt"; parse_as=:text)
3 handles
# examples/notes.txt:
  1 - 1: First note.
  3 - 3: Second note.
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

Files modified outside CodeEdit.jl are reparsed automatically when a cached timestamp changes. Call [`reindex`](@ref) to update cached handles explicitly:

```jldoctest concepts
julia> reindex("examples/DemoPackage.jl");
```
