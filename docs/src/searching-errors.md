# Finding errors from stacktraces

CodeEdit.jl can search for source blocks referenced by a stacktrace. This is useful when debugging interactively: catch the error, capture its stacktrace with `catch_backtrace()`, search project source for referenced frames, inspect the matching blocks, then edit the source and commit the fix.

```@setup searching_errors
using CodeEdit

rm("examples"; recursive=true, force=true)
srcdir = "examples"
mkpath(srcdir)
error_source = joinpath(srcdir, "error-example.jl")

write(error_source, raw"""
function inner(x)
    error("bad input: $x")
end

function outer(x)
    return inner(x + 1)
end
""")

run(`git init $srcdir`)
run(`git -C $srcdir config user.email docs@example.com`)
run(`git -C $srcdir config user.name "CodeEdit Docs"`)
run(`git -C $srcdir add .`)
run(`git -C $srcdir commit -m "Initial error example"`)

include(error_source)

#  The Documenter.jl "REPL" doesn't actually catch a stacktrace in `err` as the actual REPL would, so we cheat...
err = try
    outer(1)
catch e
    catch_backtrace()
end

sleep(1.1)
```

## Starting from a stacktrace

Suppose a function throws:

```julia
function inner(x)
    error("bad input: $x")
end

function outer(x)
    return inner(x + 1)
end
```

Capture the stacktrace:

```@repl searching_errors
trace = nothing

try
    outer(1)
catch caught
    global trace = catch_backtrace()
end;
```

Collect source handles and search for stacktrace frames:

```@repl searching_errors
hs = handles("examples", "*.jl")
matches = search(hs, trace)
```

The result contains handles for blocks whose source locations appear in the stacktrace.

## At the REPL

At the Julia REPL, the caught `ExceptionStack` is available in the variable `err`, and can be searched in the same way:

```@repl searching_errors
outer(1)
matches = search(hs, err)
```

## Inspecting the most relevant block

If the result has only a few matches, display each block:

```@repl searching_errors
for h in matches
    display(h)
end
```

A displayed handle includes the file name and line range, followed by the source block.

## Editing after locating the error

After finding the relevant block, construct a replacement and apply it through git:

```@repl searching_errors
repo = VersionControl("examples"; require_view=true)
h = only(search(matches, "error("))

fixed = replace(string(h), "error(\"bad input: \$x\")" => "throw(ArgumentError(\"bad input: \$x\"))");
edit = Replace(h, fixed)
apply!(repo, edit, "Throw ArgumentError for bad input")
```

After a successful edit, existing handles are updated or invalidated as needed. If Revise.jl is loaded, CodeEdit.jl also asks Revise to revise loaded definitions.

## Searching included files

For a package entry point that uses `include`, start from that file and follow includes recursively:

```@repl searching_errors
hs = handles(pathof(CodeEdit); includes = true);
search(hs, "search")
```

Recursive include traversal uses cycle detection, so include loops are visited at most once.
