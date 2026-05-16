```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
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
julia> h = Handle("examples/MyPackage.jl", 10)
# examples/MyPackage.jl 7 - 11:
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

## Listing handles

List all parsed blocks in one file:

```jldoctest getting_started
julia> hs = handles("examples/MyPackage.jl")
7 handles
# examples/MyPackage.jl:
   1 -  1: module MyPackage
   3 -  3: include("helpers.jl")
   5 -  5: const DEFAULT_LIMIT = 10
   7 - 11: function foo(x); y = helper(x); z = y * …
  13 - 15: function old_function_name(); return foo…
  17 - 17: end
  EOF:
```

List all blocks in files matching a glob:

```jldoctest getting_started
julia> hs = handles("examples", "*.jl")
26 handles
# examples/MyPackage.jl:
   1 -  1: module MyPackage
   3 -  3: include("helpers.jl")
   5 -  5: const DEFAULT_LIMIT = 10
   7 - 11: function foo(x); y = helper(x); z = y * …
  13 - 15: function old_function_name(); return foo…
  17 - 17: end
  EOF:

# examples/ProjectCode.jl:
   1 -  1: module ProjectCode
   3 -  3: const DEFAULT_LIMIT = 10
   5 -  7: function foo(x); return x + 1; end
   9 - 11: function helper(x); return foo(x) * 2; e…
  13 - 15: function obsolete(); return :remove_me; …
  17 - 17: end
  EOF:

# examples/concepts.jl:
  1 - 3: function foo(x); return x + 1; end
  5 - 7: function bar(x); return foo(x); end
  EOF:

# examples/error-example.jl:
  1 - 3: function inner(x); error("bad input: $x"…
  5 - 7: function outer(x); return inner(x + 1); …
  EOF:

# examples/foo.jl:
  1 - 3: function foo(x); x + 1; end
  EOF:

# examples/helpers.jl:
  1 - 1: helper(x) = x + 1
  EOF:

# examples/safety.jl:
  1 - 1: const SAFETY_VALUE = 1
  EOF:
```

Follow Julia `include` statements recursively:

```jldoctest getting_started
julia> hs = handles("examples/MyPackage.jl"; includes = true)
9 handles
# examples/MyPackage.jl:
   1 -  1: module MyPackage
   3 -  3: include("helpers.jl")
   5 -  5: const DEFAULT_LIMIT = 10
   7 - 11: function foo(x); y = helper(x); z = y * …
  13 - 15: function old_function_name(); return foo…
  17 - 17: end
  EOF:

# examples/helpers.jl:
  1 - 1: helper(x) = x + 1
  EOF:
```

## Searching handles

Search within a collection of handles:

```jldoctest getting_started
julia> hs = handles("examples", "*.jl");

julia> matches = search(hs, "old_function_name");

julia> matches
1 handle
# examples/MyPackage.jl:
  13 - 15: function old_function_name(); return foo…
```

The result is a `Set` of handles. Each matching block can be inspected, displayed, or used as the target of an edit.

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
Edit modifies examples/MyPackage.jl:
13c13
< function old_function_name()
---
> function new_function_name()

julia> apply!(repo, edit, "Rename old_function_name")
[main 8a04ce2] Rename old_function_name
 1 file changed, 1 insertion(+), 1 deletion(-)
Applied: 1 file changed, commit 8a04ce2
```

The edit is written to disk and committed to git. This is the normal CodeEdit.jl workflow: source changes become small, named commits.

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
[main 10288e6] Add another helper
 1 file changed, 2 insertions(+)
Applied: 1 file changed, commit 10288e6
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
