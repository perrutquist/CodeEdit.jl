# Getting started

## Installation

Install CodeEdit.jl from the Julia package manager. If the package is not yet registered, add it from its repository URL:

```julia-repl
pkg> add https://github.com/perrutquist/CodeEdit.jl
```

## Loading the package

```@repl getting_started
using CodeEdit
```

```@setup getting_started
rm("examples"; recursive=true, force=true)
srcdir = "examples"
mkpath(srcdir)
mypackage = joinpath(srcdir, "MyPackage.jl")
helper = joinpath(srcdir, "helpers.jl")

write(helper, """
helper(x) = x + 1
""")

write(mypackage, """
module MyPackage

include("helpers.jl")

const DEFAULT_LIMIT = 10

function foo(x)
    y = helper(x)
    z = y * 2
    return z
end

function old_function_name()
    return foo(1)
end

end
""")

run(`git init $srcdir`)
run(`git -C $srcdir config user.email docs@example.com`)
run(`git -C $srcdir config user.name "CodeEdit Docs"`)
run(`git -C $srcdir add .`)
run(`git -C $srcdir commit -m "Initial example package"`)

sleep(1.1)
```

## Creating a handle

Use [`Handle`](@ref) to point at the block containing a source location:

```@repl getting_started
h = Handle("examples/MyPackage.jl", 10)
```

If line 10 is inside a function, `h` points to the whole function block, not just that line.

Display the handle to inspect the code:

```@repl getting_started
h
```

or convert it to a string:

```@repl getting_started
source = string(h)
```

## Listing handles in files

List all blocks in one file:

```@repl getting_started
hs = handles("examples/MyPackage.jl")
```

List all blocks in files matching a glob:

```@repl getting_started
hs = handles("examples", "*.jl")
```

Follow Julia `include` statements recursively:

```@repl getting_started
hs = handles("examples/MyPackage.jl"; includes = true)
```

## Searching text

Search within a set of handles:

```@repl getting_started
hs = handles("examples", "*.jl")
matches = search(hs, "old_function_name")
matches
```

The search result is a `Set` of handles, so you can inspect or edit each matching block.

## Applying an edit with git

Create a git-backed version-control specification for the repository:

```@repl getting_started
repo = VersionControl("examples"; require_view=true)
```

With `require_view=true`, displaying the edit records the exact plan that will be checked again before application:

```@repl getting_started
h = only(search(hs, "old_function_name"))
edit = Replace(h, replace(string(h), "old_function_name" => "new_function_name"))
apply!(repo, edit, "Rename old_function_name")
```

The edit was applied to disk and committed to git.

## Inserting at the end of a file

Use [`eof_handle`](@ref) when inserting new code at the end of a file:

```@repl getting_started
h = eof_handle("examples/helpers.jl")
edit = InsertBefore(h, raw"""

another_helper(x) = helper(x) * 2
""")
apply!(repo, edit, "Add another helper")
```

## Applying without version control

For generated files, scratch files, or other workflows that should not create a commit, pass an explicit [`NoVersionControl`](@ref) specification:

```@repl getting_started
write("scratch.txt", "temporary = false\n")
h = Handle("scratch.txt", 1; parse_as=:text)
edit = Replace(h, "temporary = true\n")
apply!(NoVersionControl(require_view=true), edit)
```
