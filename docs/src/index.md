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

CodeEdit.jl provides tools for making source edits from Julia. Edits are described as ordinary Julia values, displayed as diffs, and applied explicitly.

Rather than editing line ranges directly, CodeEdit.jl operates on parsed source blocks. A [`Handle`](@ref) identifies a block; an edit such as [`Replace`](@ref) or [`InsertAfter`](@ref) describes a change to that block; [`apply!`](@ref) writes the result through a version-control backend or through [`NoVersionControl`](@ref).

## Manual

- [Getting started](getting-started.md)
- [Blocks and handles](concepts.md)
- [Searching source](searching.md)
- [Editing code](editing.md)
- [Safety and version control](safety.md)
- [Finding errors from stacktraces](searching-errors.md)
- [API reference](api.md)

## Source model

CodeEdit.jl represents source locations with [`Handle`](@ref)s. Each handle refers to one parsed block in a file. For Julia files, blocks are top-level syntactic units such as functions, types, constants, imports, exports, and includes. For text files, blocks are paragraphs separated by blank lines.

See [Blocks and handles](concepts.md) for the exact rules.

## Basic workflow

The usual workflow is explicit at each step:

```text
Handle -> Edit -> Displayed plan -> Apply -> Commit
```

The following example uses the shared documentation repository, changes one function, applies the edit, and reads the edited block back from disk.


```jldoctest index
julia> repo = VersionControl("examples"; require_view=true)
GitVersionControl("examples"; require_view=true)

julia> h = Handle("examples/DemoPackage.jl", 14)
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
Applied: 1 file changed, commit 0000000

julia> println(string(Handle("examples/DemoPackage.jl", 14)));
function increment(x)
    return x + 2
end
```

If Revise.jl is loaded, CodeEdit.jl calls Revise after a successful edit, so changed method definitions usually take effect immediately.

## Safety model

Constructing an edit does not modify the filesystem. Displaying an edit shows the planned change. With `require_view=true`, [`apply!`](@ref) verifies that the displayed plan is still current before writing any files.

The standard workflow applies edits through git and records each successful edit as a commit. See [Safety and version control](safety.md) for details.
