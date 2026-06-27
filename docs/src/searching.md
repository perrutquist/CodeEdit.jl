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

Searches operate on parsed blocks. Results can be displayed, filtered, combined, or passed directly to patch constructors.

The usual pattern is:

```text
workspace -> find -> inspect -> patch
```

## Searching a workspace

Create a workspace, then search it by string:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> find(ws, "old_function_name")
1 block
# examples/DemoPackage.jl:
 17 - 19: function old_function_name(); return foo…
```

Display a match to see the full block:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> b = only(find(ws, "old_function_name"));

julia> println(b)
# examples/DemoPackage.jl 17 - 19:
function old_function_name()
 return foo(1)
end

```

## Search aliases

[`search`](@ref) and [`grep`](@ref) are equivalent aliases for [`find`](@ref):

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> search(ws, "DEFAULT_LIMIT")
1 block
# examples/DemoPackage.jl:
 5 - 5: const DEFAULT_LIMIT = 10

julia> grep(ws, "DEFAULT_LIMIT")
1 block
# examples/DemoPackage.jl:
 5 - 5: const DEFAULT_LIMIT = 10
```

## Regex searches

Use a regular expression when the exact text is not known:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> find(ws, r"function .*increment")
1 block
# examples/DemoPackage.jl:
 13 - 15: function increment(x); return x + 1; end
```

## Restricting by file glob

Pass `files=` to search only matching paths inside a workspace:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> find(ws, "helper"; files="**/*.jl")
2 blocks
# examples/DemoPackage.jl:
 3 - 3: include("helpers.jl")
 7 - 11: function foo(x); y = helper(x); z = y * …

# examples/helpers.jl:
 1 - 1: helper(x) = x + 1
```

## Searching files and globs directly

A workspace is not required for one-off searches:

```jldoctest searching
julia> ensure_examples!();

julia> find("examples/DemoPackage.jl", "DEFAULT_LIMIT")
1 block
# examples/DemoPackage.jl:
 5 - 5: const DEFAULT_LIMIT = 10
```

```jldoctest searching
julia> ensure_examples!();

julia> find("examples/**/*.jl", "old_function_name")
1 block
# examples/DemoPackage.jl:
 17 - 19: function old_function_name(); return foo…
```

## Searching inside a block collection

You can search any block collection, not only a workspace:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> bs = blocks(ws);

julia> find(bs, "function increment")
1 block
# examples/DemoPackage.jl:
 13 - 15: function increment(x); return x + 1; end
```

## Predicate searches

Users can filter with ordinary Julia predicates:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> find(ws) do b
           occursin("function", source(b)) && endswith(path(b), "DemoPackage.jl")
       end
4 blocks
# examples/DemoPackage.jl:
 7 - 11: function foo(x); y = helper(x); z = y * …
 13 - 15: function increment(x); return x + 1; end
 17 - 19: function old_function_name(); return foo…
 21 - 23: function obsolete(); return :remove_me; …
```

This is equivalent to filtering `blocks(ws)` directly.

## Block collections and order

Search results over ordinary code behave like sets of blocks. Standard set operations can therefore be used to combine them:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> funcs = find(ws, "function");

julia> old = find(ws, "old_function_name");

julia> intersect(funcs, old)
1 block
# examples/DemoPackage.jl:
 17 - 19: function old_function_name(); return foo…
```

When order matters, convert to a vector and sort explicitly:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> sort(collect(find(ws, "function")))
6-element Vector{Block}:
 # examples/DemoPackage.jl 7 - 11: function foo(x) …
 # examples/DemoPackage.jl 13 - 15: function increment(x) …
 # examples/DemoPackage.jl 17 - 19: function old_function_name() …
 # examples/DemoPackage.jl 21 - 23: function obsolete() …
 # examples/error-example.jl 1 - 3: function inner(x) …
 # examples/error-example.jl 5 - 7: function outer(x) …
```

Stacktrace-derived block collections preserve stacktrace order instead; see [Finding blocks from stacktraces](searching-errors.md).

## Extracting a single block

A search that returns exactly one block can be passed to `only`:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> b0 = only(find(ws, "function foo"))
# examples/DemoPackage.jl 7 - 11:
function foo(x)
 y = helper(x)
 z = y * 2
 return z
end
```

You can also select the same block with a `path:line` selector:

```jldoctest searching
julia> ensure_examples!();

julia> ws = workspace("examples");

julia> b1 = ws["DemoPackage.jl:10"];

julia> b2 = block("examples/DemoPackage.jl:10");

julia> b3 = only(filter(b -> occursin("DemoPackage", path(b)) && 10 in lines(b), blocks(ws)));

julia> b0 = only(find(ws, "function foo"));

julia> b0 == b1 == b2 == b3
true
```
