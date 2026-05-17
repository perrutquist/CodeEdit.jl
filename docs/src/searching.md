```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    if !@isdefined(_searching_examples_ready)
        ensure_examples!()
        _searching_examples_ready = true
    end
end
```

# Searching source

CodeEdit.jl searches parsed blocks rather than raw line ranges. Search results are handles, so any result can be displayed, inspected, or used as the target of an edit.

The usual pattern is:

```text
Collect handles -> Search handles -> Inspect matches -> Edit a match
```

## Searching a file

Collect handles for one file with [`handles`](@ref), then search them by string:

```jldoctest searching
julia> hs = handles("examples/DemoPackage.jl");

julia> search(hs, "old_function_name")
1 handle
# examples/DemoPackage.jl:
  17 - 19: function old_function_name(); return foo…
```

Display a match to see the full block:

```jldoctest searching
julia> h = only(search(hs, "old_function_name"));

julia> println(h)
# examples/DemoPackage.jl 17 - 19:
function old_function_name()
    return foo(1)
end

```

## Regex searches

Use a regular expression when the exact text is not known:

```jldoctest searching
julia> search(hs, r"function .*increment")
1 handle
# examples/DemoPackage.jl:
  13 - 15: function increment(x); return x + 1; end
```

## Searching files and directories

You can collect handles from files matching a glob:

```jldoctest searching
julia> hs = handles("examples", "*.jl")
14 handles
# examples/DemoPackage.jl:
   1 -  1: module DemoPackage
   3 -  3: include("helpers.jl")
   5 -  5: const DEFAULT_LIMIT = 10
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

For common cases, [`search`](@ref) can collect handles and search in one call:

```jldoctest searching
julia> search("examples/DemoPackage.jl", "DEFAULT_LIMIT")
1 handle
# examples/DemoPackage.jl:
  5 - 5: const DEFAULT_LIMIT = 10
```

## Following includes

For Julia entry-point files, pass `includes=true` to follow `include` statements recursively:

```jldoctest searching
julia> handles("examples/DemoPackage.jl"; includes = true)
11 handles
# examples/DemoPackage.jl:
   1 -  1: module DemoPackage
   3 -  3: include("helpers.jl")
   5 -  5: const DEFAULT_LIMIT = 10
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

## Result order

Search results are handle sets. Their displayed summary is grouped by file, but iteration order should not be used as a relevance signal. If order matters, sort results explicitly using [`filepath`](@ref) and [`lines`](@ref), or select a single result with `only` when you expect exactly one match.
