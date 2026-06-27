```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    if !@isdefined(_getting_started_examples_ready)
        ensure_examples!()
        _getting_started_examples_ready = true
    end
end
```

# Getting started

This chapter introduces the high-level CodeEdit.jl workflow: open a workspace, find a block, build a patch, review the plan, and apply it.

(In the examples, we use a small git repository in a directory `examples`. The file `docs/meta_setup.jl` creates this repo.)

## Installation

Install CodeEdit.jl with Julia's package manager. The package is not yet registered, so add it from its repository URL:

```julia-repl
pkg> add https://github.com/perrutquist/CodeEdit.jl
```

## Loading the package

```jldoctest getting_started
julia> using CodeEdit
```

## Opening a workspace

For source edits in a git repository, start with [`workspace`](@ref):

```jldoctest getting_started
julia> ws = workspace("examples")
Workspace("examples"; git=true, review=true)
```

[`repo`](@ref), [`project`](@ref), and [`codebase`](@ref) are equivalent aliases. The canonical spelling in the manual is `workspace`.

## Finding blocks

Search a workspace directly with [`find`](@ref):

```jldoctest getting_started
julia> ws = workspace("examples");

julia> find(ws, "old_function_name")
1 block
# examples/DemoPackage.jl:
  17 - 19: function old_function_name(); return foo…
```

A block can be displayed, converted to source text, or passed directly to a patch constructor:

```jldoctest getting_started
julia> ws = workspace("examples");

julia> b = only(find(ws, "function foo"))
# examples/DemoPackage.jl 7 - 11:
function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

julia> source(b)
"function foo(x)\n    y = helper(x)\n    z = y * 2\n    return z\nend\n"
```

You can also select a block by file and line number:

```jldoctest getting_started
julia> ws = workspace("examples");

julia> ws["DemoPackage.jl:7"]
# examples/DemoPackage.jl 7 - 11:
function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

julia> block("examples/DemoPackage.jl:10")
# examples/DemoPackage.jl 7 - 11:
function foo(x)
    y = helper(x)
    z = y * 2
    return z
end
```

!!! warning
    Do not rely on a displayed line number after later edits have changed the file. Re-select the block from the current file contents before building a new patch.

!!! note
    A selector that points inside a block returns the whole block, not only the selected line.

See [Searching source](searching.md) for regex searches, glob-restricted searches, predicate searches, and searches over files directly.

## Replacing source and committing the change

To change source, construct a patch and apply it.

With `review=true`, displaying the patch records the reviewed plan. When [`apply!`](@ref) runs, CodeEdit.jl replans the patch and refuses to write if the current diff no longer matches what you reviewed.

!!! note
    In the REPL, evaluating a patch without a trailing semicolon displays it. Calling `display(patch)` is equivalent.

```jldoctest getting_started
julia> ws = workspace("examples");

julia> b = only(find(ws, "old_function_name"));

julia> p = replace(b, "old_function_name" => "new_function_name")
Patch modifies examples/DemoPackage.jl:
17c17
< function old_function_name()
---
> function new_function_name()

julia> apply!(p, "Rename old_function_name")
Applied: 1 file changed, commit 3630f3e
```

The patch is written to disk and committed to git with the message you provide.

## Appending to a file

Use [`append_to`](@ref) when you want to add new text at the end of a file without first selecting an EOF block:

```jldoctest getting_started
julia> p = append_to("examples/helpers.jl", raw"""
       
       another_helper(x) = helper(x) * 2
       """)
Patch modifies examples/helpers.jl:
1c2,3
---
>
> another_helper(x) = helper(x) * 2

julia> apply!(p, "Add another helper")
Applied: 1 file changed, commit c58b1c4
```

## Applying without git

For generated files, scratch files, or other changes that should not create a commit, either create a non-git workspace or pass `git=false` to [`apply!`](@ref):

```jldoctest getting_started
julia> write("scratch.txt", "temporary = false\n");

julia> b = block("scratch.txt:1"; as=:text)
# scratch.txt 1 - 1:
temporary = false

julia> p = replace(b, "false" => "true")
Patch modifies scratch.txt:
1c1
< temporary = false
---
> temporary = true

julia> apply!(p; git=false)
Applied: 1 file changed
```
