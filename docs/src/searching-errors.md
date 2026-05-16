```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    include("examples/error-example.jl")
end
```

# Finding errors from stacktraces

CodeEdit.jl can search for source blocks referenced by a stacktrace. This makes a debugging session into an editing workflow: catch the error, capture the stacktrace with `catch_backtrace()`, search project source for referenced frames, inspect the matching blocks, then edit the source and commit the fix.


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

Capture the stacktrace:

```jldoctest searching_errors
julia> outer(1)
ERROR: bad input: 2
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:44
 [2] inner(x::Int64)
   @ Main ~/Documents/Julia/CodeEdit/docs/examples/error-example.jl:2
 [3] outer(x::Int64)
   @ Main ~/Documents/Julia/CodeEdit/docs/examples/error-example.jl:6
 [4] top-level scope
   @ none:1

julia> trace = try
           outer(1)
       catch caught
           catch_backtrace()
       end;
```

Collect source handles and search for frames from the captured stacktrace:

```jldoctest searching_errors
julia> hs = handles("examples", "*.jl");

julia> matches = search(hs, trace)
2 handles
# examples/error-example.jl:
  1 - 3: function inner(x); error("bad input: $x"…
  5 - 7: function outer(x); return inner(x + 1); …
```

The result contains handles for blocks whose source locations occur in the stacktrace.

## At the REPL

In a REPL session, capture the thrown stacktrace in a variable such as `err` and search it in the same way:

```jldoctest searching_errors
julia> err = try
           outer(1)
       catch caught
           catch_backtrace()
       end;

julia> matches = search(hs, err)
2 handles
# examples/error-example.jl:
  1 - 3: function inner(x); error("bad input: $x"…
  5 - 7: function outer(x); return inner(x + 1); …
```

## Inspecting the most relevant block

If the result contains only a few matches, display each block:

```jldoctest searching_errors
julia> for h in matches
          println(h)
       end
# examples/error-example.jl 5 - 7:
function outer(x)
    return inner(x + 1)
end

# examples/error-example.jl 1 - 3:
function inner(x)
    error("bad input: $x")
end

```

A displayed handle includes the file name and line range, followed by the source block.

## Editing after locating the error

After finding the relevant block, construct a replacement and apply it through git:

```jldoctest searching_errors
julia> repo = VersionControl("examples"; require_view=true);

julia> h = only(search(matches, "error("));

julia> fixed = replace(string(h), "error(\"bad input: \$x\")" => "throw(ArgumentError(\"bad input: \$x\"))");

julia> edit = Replace(h, fixed)
Edit modifies examples/error-example.jl:
2c2
<     error("bad input: $x")
---
>     throw(ArgumentError("bad input: $x"))

julia> apply!(repo, edit, "Throw ArgumentError for bad input")
[main b52c24f] Throw ArgumentError for bad input
 1 file changed, 1 insertion(+), 1 deletion(-)
Applied: 1 file changed, commit b52c24f
```

After a successful edit, existing handles are updated or invalidated as needed. If Revise.jl is loaded, CodeEdit.jl asks Revise to revise loaded definitions.

## Searching included files

For a package entry point that uses `include`, start from that file and follow includes recursively:

```jldoctest searching_errors
julia> hs = handles(pathof(CodeEdit); includes = true);

julia> search(hs, "search")
15 handles
# /Users/rutquist/Documents/Julia/CodeEdit/src/CodeEdit.jl:
  22 - 22: include("search.jl")
  31 - 31: export search

# /Users/rutquist/Documents/Julia/CodeEdit/src/search.jl:
   74 -  88: "search(handle_set, needle::AbstractStri…
   90 - 104: "search(handle_set, needle::Regex) Searc…
  106 - 121: "search(handle_set, trace) Search an exi…
  123 - 130: "search(path::AbstractString, needle::Ab…
  132 - 139: "search(path::AbstractString, needle::Re…
  141 - 148: "search(paths::AbstractVector{<:Abstract…
  150 - 157: "search(paths::AbstractVector{<:Abstract…
  159 - 172: "search(root::AbstractString, pattern::A…
  174 - 187: "search(root::AbstractString, pattern::A…
  189 - 196: "search(repo::VersionControl, needle::Ab…
  198 - 205: "search(repo::VersionControl, needle::Re…
  207 - 215: "search(repo::VersionControl, trace) Sea…

# /Users/rutquist/Documents/Julia/CodeEdit/src/spans.jl:
  116 - 134: "Return the line range touched by `span`…
```

Recursive include traversal uses cycle detection, so include loops are visited at most once.
