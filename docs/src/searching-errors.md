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

# Finding errors from stacktraces

CodeEdit.jl can locate source blocks referenced by a stacktrace. This makes a debugging session into an editing workflow: catch the error, capture the stacktrace with `catch_backtrace()`, map frames to handles, inspect the matching blocks, then edit the source and commit the fix.


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

Let's display the intersection of (blocks in our code) with (blocks in the trace), in the order that they appear in the trace.

```jldoctest searching_errors
julia> hs = handles("examples", "*.jl");

julia> for h in Handle.(trace)
          if h in hs
              println(h)
          end
       end
# examples/error-example.jl 1 - 3:
function inner(x)
    error("bad input: $x")
end

# examples/error-example.jl 5 - 7:
function outer(x)
    return inner(x + 1)
end

```
A displayed handle includes the file name and line range, followed by the source block.

## Editing after locating the error

After finding the relevant block, construct a replacement and apply it through git:

```jldoctest searching_errors
julia> repo = VersionControl("examples"; require_view=true);

julia> h = only(search(intersect(hs, Handle.(trace)), "error("))
# examples/error-example.jl 1 - 3:
function inner(x)
    error("bad input: $x")
end

julia> fixed = replace(string(h), "error(\"bad input: \$x\")" => "throw(ArgumentError(\"bad input: \$x\"))");

julia> edit = Replace(h, fixed)
Edit modifies examples/error-example.jl:
2c2
<     error("bad input: $x")
---
>     throw(ArgumentError("bad input: $x"))

julia> apply!(repo, edit, "Throw ArgumentError for bad input")
Applied: 1 file changed, commit 751de5e
```

After a successful edit, existing handles are updated or invalidated as needed.

For ordinary string, regex, glob, and recursive include searches, see [Searching source](searching.md).
