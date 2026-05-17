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

This chapter introduces the basic CodeEdit.jl workflow: find a block, construct an edit, review the plan, and apply the change deliberately.

The documentation examples share a small git repository in `examples` and commit each successful source edit.

## Installation

Install CodeEdit.jl with Julia's package manager. If the package is not registered, add it from its repository URL:

```julia-repl
pkg> add https://github.com/perrutquist/CodeEdit.jl
```

## Loading the package

```jldoctest getting_started
julia> using CodeEdit
```

## Creating a handle

CodeEdit.jl starts from source locations, but edits operate on blocks rather than on raw line ranges. Use [`Handle`](@ref) to refer to the block containing a location:

```jldoctest getting_started
julia> h = Handle("examples/DemoPackage.jl", 10)
# examples/DemoPackage.jl 7 - 11:
function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

```

If line 10 is inside a function, `h` refers to the whole function block, not only to that line.

```jldoctest getting_started
julia> source = string(h)
"function foo(x)\n    y = helper(x)\n    z = y * 2\n    return z\nend\n"
```

## Listing and searching handles

List the parsed blocks in a file with [`handles`](@ref):

```jldoctest getting_started
julia> hs = handles("examples/DemoPackage.jl")
9 handles
# examples/DemoPackage.jl:
   1 -  1: module DemoPackage
   3 -  3: include("helpers.jl")
   5 -  5: const DEFAULT_LIMIT = 10
   7 - 11: function foo(x); y = helper(x); z = y * …
  13 - 15: function increment(x); return x + 1; end
  17 - 19: function old_function_name(); return foo…
  21 - 23: function obsolete(); return :remove_me; …
  25 - 25: end
  EOF:
```

Search within those handles to find a block by text:

```jldoctest getting_started
julia> matches = search(hs, "old_function_name")
1 handle
# examples/DemoPackage.jl:
  17 - 19: function old_function_name(); return foo…
```

The result can be inspected, displayed, or used as the target of an edit. See [Searching source](searching.md) for glob searches, regex searches, and recursive `include` traversal.

## Applying an edit with git

Inspecting handles does not modify files. To change source, construct an edit value and choose how it should be applied.

For ordinary source changes, use a git-backed version-control specification:

```jldoctest getting_started
julia> repo = VersionControl("examples"; require_view=true)
GitVersionControl("examples"; require_view=true)
```

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

The edit is written to disk and committed to git. Each successful git-backed edit is committed with the message you provide.

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
