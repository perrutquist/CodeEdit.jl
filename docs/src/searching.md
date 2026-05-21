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

Searches operate on parsed blocks. Results are handles that can be displayed, inspected, filtered, combined, or passed to edit constructors.

The usual pattern is:

```text
VersionControl -> handles -> search -> inspect -> edit
```

## Searching a repository

Create a version-control context, collect handles with [`handles`](@ref), then search them by string:

```jldoctest searching
julia> repo = VersionControl("examples"; require_view=true);

julia> hs = handles(repo);

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

You can also collect handles directly from a file or from files matching a glob:

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

## Handle sets and order

[`handles`](@ref) and [`search`](@ref) return sets. A handle appears at most once in a set, and standard set operations can be used to combine search results:

```julia
functions = search(hs, "function")
limits = search(hs, "DEFAULT_LIMIT")
targets = union(functions, limits)
```

The displayed summary is grouped by file and sorted for readability. Iterating over a set yields arbitrary order. If order matters, use `sort!(collect(hs))` to produce a vector in display order.

Use a vector when the input order has meaning. For example, `Handle.(stacktrace)` preserves stacktrace order; see [Finding errors from stacktraces](searching-errors.md).

# Extracting a single handle from a search

A `search` or `filter` operation that returns a single handle can be passed to the `only` function to extract that handle, for example:

```jldoctest searching
julia> h1 = only(search(hs, "function foo"))
# examples/DemoPackage.jl 7 - 11:
function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

```

A simple way is often to use the `Handle` constructor with the filename and line number, although this can be brittle as line numbers can change due to edits.

```jldoctest searching
julia> h2 = Handle("examples/DemoPackage.jl", 10);

julia> h3 = only(filter(h -> occursin("DemoPackage", filepath(h)) && 10 in lines(h), hs));

julia> h1 === h2 === h3
true

```
