# Getting started

## Installation

Install CodeEdit.jl from the Julia package manager. If the package is not yet registered, add it from its repository URL:

```julia-repl
pkg> add https://github.com/perrutquist/CodeEdit.jl
```

## Loading the package

```@repl getting_started
using CodeEdit
```

```@setup getting_started
rm("examples"; recursive=true, force=true)
srcdir = "examples"
mkpath(srcdir)
mypackage = joinpath(srcdir, "MyPackage.jl")
helper = joinpath(srcdir, "helpers.jl")
append_example = joinpath(srcdir, "append-example.jl")

write(helper, """
helper(x) = x + 1
""")

write(append_example, """
const APPEND_EXAMPLE = true
""")

write(mypackage, """
module MyPackage

include("helpers.jl")

const DEFAULT_LIMIT = 10

function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

function old_function_name()
    return foo(1)
end

end
""")
```

## Creating a handle

Use [`Handle`](@ref) to point at the block containing a source location:

```@repl getting_started
h = Handle("examples/MyPackage.jl", 10)
```

If line 10 is inside a function, `h` points to the whole function block, not just that line.

Display the handle to inspect the code:

```@repl getting_started
h
```

or convert it to a string:

```@repl getting_started
source = string(h)
```

## Listing handles in files

List all blocks in one file:

```@repl getting_started
hs = handles("examples/MyPackage.jl")
```

List all blocks in files matching a glob:

```@repl getting_started
hs = handles("examples", "*.jl")
```

Follow Julia `include` statements recursively:

```@repl getting_started
hs = handles("examples/MyPackage.jl"; includes = true)
```

## Getting the end-of-file handle

Use [`eof_handle`](@ref) when inserting new code at the end of a file:

```@repl getting_started
h = eof_handle("examples/append-example.jl")
edit = InsertBefore(h, raw"""
function new_function()
    return nothing
end

""")
```

## Searching text

Search within a set of handles:

```@repl getting_started
hs = handles("examples", "*.jl")
matches = search(hs, "old_function_name")
matches
```

The search result is a `Set` of handles, so you can inspect or edit each matching block.
