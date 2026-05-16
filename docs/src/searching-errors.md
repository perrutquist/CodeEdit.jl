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
```

## Inspecting the most relevant block

If the result contains only a few matches, display each block:

```jldoctest searching_errors
julia> for h in matches
           display(h)
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

julia> apply!(repo, edit, "Throw ArgumentError for bad input")
```

After a successful edit, existing handles are updated or invalidated as needed. If Revise.jl is loaded, CodeEdit.jl asks Revise to revise loaded definitions.

## Searching included files

For a package entry point that uses `include`, start from that file and follow includes recursively:

```jldoctest searching_errors
julia> hs = handles(pathof(CodeEdit); includes = true);

julia> search(hs, "search")
```

Recursive include traversal uses cycle detection, so include loops are visited at most once.
