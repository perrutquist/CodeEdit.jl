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
```

If line 10 is inside a function, `h` refers to the whole function block, not only to that line.

Display the handle to inspect the code:

```jldoctest getting_started
julia> h
```

or convert it to a string:

```jldoctest getting_started
julia> source = string(h)
```

## Listing handles

List all parsed blocks in one file:

```jldoctest getting_started
julia> hs = handles("examples/MyPackage.jl")
```

List all blocks in files matching a glob:

```jldoctest getting_started
julia> hs = handles("examples", "*.jl")
```

Follow Julia `include` statements recursively:

```jldoctest getting_started
julia> hs = handles("examples/MyPackage.jl"; includes = true)
```

## Searching handles

Search within a collection of handles:

```jldoctest getting_started
julia> hs = handles("examples", "*.jl");

julia> matches = search(hs, "old_function_name");

julia> matches
```

The result is a `Set` of handles. Each matching block can be inspected, displayed, or used as the target of an edit.

## Applying an edit with git

Inspecting handles does not modify files. To change source, construct an edit value and choose how it should be applied.

For ordinary source changes, use a git-backed version-control specification:

```jldoctest getting_started
julia> repo = VersionControl("examples"; require_view=true)
```

With `require_view=true`, displaying the edit records the exact plan. When [`apply!`](@ref) runs, CodeEdit.jl plans the edit again and refuses to apply it if the current plan differs from the displayed one:

!!! note
    In the REPL, evaluating an edit without a trailing semicolon displays it. Calling `display(edit)` is equivalent.

```jldoctest getting_started
julia> h = only(search(hs, "old_function_name"));

julia> edit = Replace(h, replace(string(h), "old_function_name" => "new_function_name"))

julia> apply!(repo, edit, "Rename old_function_name")
```

The edit is written to disk and committed to git. This is the normal CodeEdit.jl workflow: source changes become small, named commits.

## Inserting at the end of a file

Use [`eof_handle`](@ref) when inserting new code at the end of a file:

```jldoctest getting_started
julia> h = eof_handle("examples/helpers.jl");

julia> edit = InsertBefore(h, raw"""
       
       another_helper(x) = helper(x) * 2
       """)

julia> apply!(repo, edit, "Add another helper")
```

## Applying without version control

For generated files, scratch files, or other changes that should not create a commit, pass an explicit [`NoVersionControl`](@ref) specification:

```jldoctest getting_started
julia> write("scratch.txt", "temporary = false\n");

julia> h = Handle("scratch.txt", 1; parse_as=:text);

julia> edit = Replace(h, "temporary = true\n")

julia> apply!(NoVersionControl(require_view=true), edit)
```
