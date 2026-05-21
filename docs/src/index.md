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

CodeEdit.jl provides tools for making source edits from Julia. A [`Handle`](@ref) identifies a parsed source block, edit constructors such as [`Replace`](@ref) and [`InsertAfter`](@ref) describe changes, and [`apply!`](@ref) writes the result through an explicit version-control specification.

## Manual

- [Getting started](getting-started.md)
- [Blocks and handles](concepts.md)
- [Searching source](searching.md)
- [Editing code](editing.md)
- [Safety and version control](safety.md)
- [Finding errors from stacktraces](searching-errors.md)
- [API reference](api.md)

## Basic workflow

A common workflow starts by choosing a version-control context and collecting handles from it:

```text
VersionControl -> handles -> search/select -> edit -> apply!
```

The following example changes one function in a repository, applies the edit, and reads the edited block back from disk.


```jldoctest index
julia> repo = VersionControl("examples"; require_view=true)
GitVersionControl("examples"; require_view=true)

julia> hs = handles(repo);

julia> h = only(search(hs, "function increment"))
# examples/DemoPackage.jl 13 - 15:
function increment(x)
    return x + 1
end

julia> replacement = replace(string(h), "x + 1" => "x + 2");

julia> edit = Replace(h, replacement)
Edit modifies examples/DemoPackage.jl:
14c14
<     return x + 1
---
>     return x + 2

julia> apply!(repo, edit, "Change increment")
Applied: 1 file changed, commit 4c0ffee

julia> println(string(Handle("examples/DemoPackage.jl", 14)));
function increment(x)
    return x + 2
end
```

If Revise.jl is loaded, CodeEdit.jl calls Revise after a successful edit, so changed method definitions usually take effect immediately.

See [Blocks and handles](concepts.md) for the source model and [Safety and version control](safety.md) for review, validation, and git behavior.
