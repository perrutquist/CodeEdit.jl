# Getting started

## Loading the package

```julia
using CodeEdit
```

## Creating a handle

Use [`Handle`](@ref) to point at the block containing a source location:

```julia
h = Handle("src/MyPackage.jl", 10)
```

If line 10 is inside a function, `h` points to the whole function block, not just that line.

Display the handle to inspect the code:

```julia
display(h)
```

or convert it to a string:

```julia
source = string(h)
```

## Listing handles in files

List all blocks in one file:

```julia
hs = handles("src/MyPackage.jl")
```

List all blocks in files matching a glob:

```julia
hs = handles("src", "*.jl")
```

Follow Julia `include` statements recursively:

```julia
hs = handles("src/MyPackage.jl"; includes = true)
```

## Getting the end-of-file handle

Use [`eof_handle`](@ref) when inserting new code at the end of a file:

```julia
h = eof_handle("src/MyPackage.jl")
edit = InsertBefore(h, raw"""
function new_function()
    return nothing
end

""")
```

## Searching text

Search within a set of handles:

```julia
hs = handles("src", "*.jl")
matches = search(hs, "old_function_name")
display(matches)
```

The search result is a `Set` of handles, so you can inspect or edit each matching block.
