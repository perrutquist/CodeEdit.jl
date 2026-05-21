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

This chapter introduces the basic CodeEdit.jl workflow: choose a version-control context, collect handles, find a block, construct an edit, review the plan, and apply it.

The documentation examples share a small git repository in `examples`.

## Installation

Install CodeEdit.jl with Julia's package manager. If the package is not registered, add it from its repository URL:

```julia-repl
pkg> add https://github.com/perrutquist/CodeEdit.jl
```

## Loading the package

```jldoctest getting_started
julia> using CodeEdit
```

## Creating a repository context

For source edits in a git repository, start with [`VersionControl`](@ref):

```jldoctest getting_started
julia> repo = VersionControl("examples"; require_view=true)
GitVersionControl("examples"; require_view=true)
```

The same `repo` value is used to collect editable handles and to apply edits later.

## Listing and searching handles

Collect parsed source blocks from the repository with [`handles`](@ref):

```jldoctest getting_started
julia> hs = handles(repo);

julia> matches = search(hs, "old_function_name")
1 handle
# examples/DemoPackage.jl:
  17 - 19: function old_function_name(); return foo…
```

Search results are handles. A handle can be inspected, displayed, converted to source text, or passed to an edit constructor:

```jldoctest getting_started
julia> h = only(search(hs, "function foo"))
# examples/DemoPackage.jl 7 - 11:
function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

julia> source = string(h)
"function foo(x)\n    y = helper(x)\n    z = y * 2\n    return z\nend\n"
```

You can also look up a unique handle in a collection by filepath suffix and source line with [`handle_at`](@ref), or equivalently by indexing with a `path:line` key:

```jldoctest getting_started
julia> hs["DemoPackage.jl:7"]
# examples/DemoPackage.jl 7 - 11:
function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

```

Direct construction with [`Handle`](@ref) is useful when you already have a file and line number:

```jldoctest getting_started
julia> Handle("examples/DemoPackage.jl", 10)
# examples/DemoPackage.jl 7 - 11:
function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

```

See [Searching source](searching.md) for glob searches, regex searches, recursive `include` traversal, and set operations on handle collections.

## Applying an edit with git

Inspecting handles leaves files unchanged. To change source, construct an edit value and apply it through the repository.

With `require_view=true`, displaying the edit records the exact plan. When [`apply!`](@ref) runs, CodeEdit.jl plans the edit again and refuses to apply it if the current plan differs from the displayed one:

!!! note
    In the REPL, evaluating an edit without a trailing semicolon displays it. Calling `display(edit)` is equivalent.

```jldoctest getting_started
julia> h = only(search(hs, "old_function_name"));

julia> edit = Replace(h, replace(string(h), "old_function_name" => "new_function_name"))
Edit modifies examples/DemoPackage.jl:
17c17
< function old_function_name()
---
> function new_function_name()

julia> apply!(repo, edit, "Rename old_function_name")
Applied: 1 file changed, commit 3630f3e
```

The edit is written to disk and committed to git with the message you provide.

## Inserting at the end of a file

Use [`eof_handle`](@ref) when inserting new code at the end of a file:

```jldoctest getting_started
julia> h = eof_handle("examples/helpers.jl");

julia> edit = InsertBefore(h, raw"""
       
       another_helper(x) = helper(x) * 2
       """)
Edit modifies examples/helpers.jl:
1c2,3
---
>
> another_helper(x) = helper(x) * 2

julia> apply!(repo, edit, "Add another helper")
Applied: 1 file changed, commit c58b1c4
```

## Applying without version control

For generated files, scratch files, or other changes that should not create a commit, pass an explicit [`NoVersionControl`](@ref) specification:

```jldoctest getting_started
julia> write("scratch.txt", "temporary = false\n");

julia> h = Handle("scratch.txt", 1; parse_as=:text);

julia> edit = Replace(h, "temporary = true\n")
Edit modifies scratch.txt:
1c1
< temporary = false
---
> temporary = true

julia> apply!(NoVersionControl(require_view=true), edit)
Applied: 1 file changed
```
