```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    if !@isdefined(_searching_errors_examples_ready)
        ensure_examples!()
        _searching_errors_examples_ready = true
    end
    include("examples/error-example.jl")
end
```

# Finding blocks from stacktraces

CodeEdit.jl can locate source blocks referenced by a stacktrace. This turns a debugging session into an editing workflow: catch the error, capture the stacktrace with `catch_backtrace()`, map frames to blocks, inspect the relevant source, then build and apply a patch.

## Starting from a stacktrace

Suppose the following call throws an exception:

```julia
function inner(x)
    error("bad input: $x")
end

function outer(x)
    return inner(x + 1)
end
```

The thrown error contains stack frames for both functions:

```julia-repl
julia> outer(1)
ERROR: bad input: 2
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:44
 [2] inner(x::Int64)
   @ Main .../docs/examples/error-example.jl:2
 [3] outer(x::Int64)
   @ Main .../docs/examples/error-example.jl:6
```

Capture the backtrace in a variable:

```jldoctest searching_errors
julia> trace = try
           outer(1)
       catch
           stacktrace(catch_backtrace())
       end;
```

## Inspecting the most relevant blocks

Display the blocks in our code that appear in the trace, preserving stacktrace order:

```jldoctest searching_errors
julia> ws = workspace("examples");

julia> blocks(trace; in=ws)
# examples/error-example.jl 1 - 3: function inner(x); error("bad input: $x"…
# examples/error-example.jl 5 - 7: function outer(x); return inner(x + 1); …
```

Stacktrace-derived block collections preserve stack order, so they return a vector rather than a set-like block collection.

## Editing after locating the error

After finding the relevant block, construct a replacement and apply it through git:

```jldoctest searching_errors
julia> ws = workspace("examples");

julia> b = only(find(blocks(trace, in=ws), "error("))
# examples/error-example.jl 1 - 3:
function inner(x)
    error("bad input: $x")
end
 
julia> p = replace(
           b,
           raw"""error("bad input: $x")""" =>
           raw"""throw(ArgumentError("bad input: $x"))""",
       )
Patch modifies examples/error-example.jl:
2c2
<     error("bad input: $x")
---
>     throw(ArgumentError("bad input: $x"))

julia> apply!(p, "Throw ArgumentError for bad input")
Applied: 1 file changed, commit 1c6371a

```

After a successful apply, existing blocks are updated or invalidated as needed.

For ordinary string, regex, glob, and recursive include searches, see [Searching source](searching.md).
