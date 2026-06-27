```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    if !@isdefined(_index_examples_ready)
        ensure_examples!()
        _index_examples_ready = true
    end
end
```

# CodeEdit.jl

CodeEdit.jl lets you search source as blocks, plan changes as patches, and apply them safely from Julia.

The high-level model is:

```text
workspace -> blocks -> patches -> apply!/commit!
```

A Julia programmer who already understands files, git, grep, diffs, and stacktraces should be able to use the package almost immediately.

## Manual

- [Getting started](getting-started.md)
- [Workspaces and blocks](concepts.md)
- [Searching source](searching.md)
- [Editing code](editing.md)
- [Safety and version control](safety.md)
- [Finding blocks from stacktraces](searching-errors.md)
- [API reference](api.md)

## Basic workflow

A [`Workspace`](@ref) represents the codebase being edited. [`find`](@ref) locates matching blocks, patch constructors such as [`replace`](@ref) and [`insert_after`](@ref) plan changes, and [`apply!`](@ref) or [`commit!`](@ref) writes the result.

A common workflow is:

1. Open a workspace.
2. Find or select a block.
3. Build a patch.
4. Review the planned diff.
5. Apply it.

The following example changes one function in a repository, applies the patch, and reads the updated block back from disk.

```jldoctest index
julia> ws = workspace("examples")
Workspace("examples"; git=true, review=true)

julia> b = only(find(ws, "function increment"))
# examples/DemoPackage.jl 13 - 15:
function increment(x)
    return x + 1
end

julia> p = replace(b, "x + 1" => "x + 2")
Patch modifies examples/DemoPackage.jl:
14c14
<     return x + 1
---
>     return x + 2

julia> apply!(p, "Change increment")
Applied: 1 file changed, commit 4c0ffee

julia> println(source(block("examples/DemoPackage.jl:14")));
function increment(x)
    return x + 2
end
```

If Revise.jl is loaded, CodeEdit.jl notifies Revise after a successful apply, so updated method definitions usually take effect immediately.

See [Workspaces and blocks](concepts.md) for the source model and [Safety and version control](safety.md) for review, validation, and git behavior.
