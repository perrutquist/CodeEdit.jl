```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    if !@isdefined(_concepts_examples_ready)
        ensure_examples!()
        _concepts_examples_ready = true
    end
end
```

# Workspaces and blocks

CodeEdit.jl edits files by first splitting them into source or text *blocks*. A [`Workspace`](@ref) is the usual entry point, and a [`Block`](@ref) is the user-facing object you inspect, search, and edit.

Patches built from blocks can be applied through git or, when needed, written without git.

## Workspaces

A workspace represents the root directory being edited:

```jldoctest concepts
julia> ensure_examples!();

julia> ws = workspace("examples")
Workspace("examples"; git=true, review=true)
```

Aliases are available for the same operation:

```jldoctest concepts
julia> ensure_examples!();

julia> repo("examples")
Workspace("examples"; git=true, review=true)

julia> project("examples")
Workspace("examples"; git=true, review=true)

julia> codebase("examples")
Workspace("examples"; git=true, review=true)
```

The canonical spelling in the manual is `workspace`.

## Blocks

For Julia files, blocks are top-level syntactic units such as functions, types, macros, constants, assignments, imports, exports, and includes. Attached docstrings stay with the block they document, so replacing a documented function keeps the docstring and function together. Use [`docstring`](@ref) or [`docs`](@ref) to inspect attached documentation.

For example, CodeEdit.jl sees a file like this as several separate blocks:

```julia
module Inventory            # block

const DEFAULT_TAX = 0.25    # block

function price_with_tax(x)  # block
    return x * (1 + DEFAULT_TAX)
end

end                         # block
                            # EOF block
```

At the end of each file, CodeEdit.jl creates a special EOF block internally so operations such as [`append_to`](@ref) can add content safely at the end of a file.

For non-Julia files, blocks are paragraphs separated by blank lines.

## Selecting a block

A selector like `path:line` returns the block containing that line:

```jldoctest concepts
julia> ensure_examples!();

julia> b = block("examples/DemoPackage.jl:14")
# examples/DemoPackage.jl 13 - 15:
function increment(x)
 return x + 1
end
```

Because line 14 is inside `increment`, the selected block spans the whole function.

The same lookup works through a workspace:

```jldoctest concepts
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> ws["DemoPackage.jl:14"]
# examples/DemoPackage.jl 13 - 15:
function increment(x)
 return x + 1
end
```

A line inside a block selects the same block as the first line of that block:

```jldoctest concepts
julia> ensure_examples!();

julia> block("examples/DemoPackage.jl:14") == block("examples/DemoPackage.jl:13")
true
```

## Reading source and metadata

The obvious names work for turning a block back into text:

```jldoctest concepts
julia> ensure_examples!();

julia> b = block("examples/DemoPackage.jl:14");

julia> source(b)
"function increment(x)\n return x + 1\nend\n"

julia> text(b)
"function increment(x)\n return x + 1\nend\n"

julia> String(b)
"function increment(x)\n return x + 1\nend\n"
```

Basic metadata is also easy to inspect:

```jldoctest concepts
julia> ensure_examples!();

julia> b = block("examples/DemoPackage.jl:14");

julia> path(b)
"examples/DemoPackage.jl"

julia> lines(b)
13:15

julia> span(b)
("examples/DemoPackage.jl", 13:15)
```

## Block collections

[`blocks`](@ref) collects blocks from a workspace, file, or glob:

```jldoctest concepts
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> blocks(ws)
14 blocks
# examples/DemoPackage.jl:
 1 - 1: module DemoPackage
 3 - 3: include("helpers.jl")
 5 - 5: const DEFAULT_LIMIT = 10
 7 - 11: function foo(x); y = helper(x); z = y * …
 13 - 15: function increment(x); return x + 1; end
 17 - 19: function old_function_name(); return foo…
 21 - 23: function obsolete(); return :remove_me; …
 25 - 25: end
 EOF:

# examples/error-example.jl:
 1 - 3: function inner(x); error("bad input: $x"…
 5 - 7: function outer(x); return inner(x + 1); …
 EOF:

# examples/helpers.jl:
 1 - 1: helper(x) = x + 1
 EOF:
```

Search results over ordinary code act like sets of blocks, so standard set operations are useful for combining selections. When order matters, convert to a vector and sort explicitly.

## Julia and text parsing

By default, `.jl` files are parsed as Julia source and other files are parsed as text. Use `as=:julia`, `as=:text`, or `as=:auto` to control parsing:

```jldoctest concepts
julia> ensure_examples!();

julia> blocks("examples/notes.txt"; as=:text)
3 blocks
# examples/notes.txt:
 1 - 1: First note.
 3 - 3: Second note.
 EOF:
```

A cached file has one parse mode at a time. Reloading the same file with a different parse mode invalidates existing blocks for that file.

## Following includes

For Julia entry-point files, pass `includes=true` or `follow_includes=true` to traverse recursive `include` statements:

```jldoctest concepts
julia> ensure_examples!();

julia> blocks("examples/DemoPackage.jl"; follow_includes=true)
11 blocks
# examples/DemoPackage.jl:
 1 - 1: module DemoPackage
 3 - 3: include("helpers.jl")
 5 - 5: const DEFAULT_LIMIT = 10
 7 - 11: function foo(x); y = helper(x); z = y * …
 13 - 15: function increment(x); return x + 1; end
 17 - 19: function old_function_name(); return foo…
 21 - 23: function obsolete(); return :remove_me; …
 25 - 25: end
 EOF:

# examples/helpers.jl:
 1 - 1: helper(x) = x + 1
 EOF:
```

Recursive include traversal uses cycle detection, so include loops are visited at most once.

## Block validity

Patches update blocks when their referenced source can still be matched after the change. Blocks are invalidated when their source is deleted or can no longer be matched unambiguously.

Use [`is_valid`](@ref) to test whether a block still refers to a valid source block:

```jldoctest concepts
julia> ensure_examples!();

julia> b = block("examples/DemoPackage.jl:14");

julia> is_valid(b)
true
```

Files modified outside CodeEdit.jl are reparsed automatically when a cached timestamp changes. Call [`reindex`](@ref) to refresh cached blocks explicitly:

```jldoctest concepts
julia> ensure_examples!();

julia> reindex("examples/DemoPackage.jl");
```
