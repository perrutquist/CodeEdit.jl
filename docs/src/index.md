# CodeEdit.jl

CodeEdit.jl locates, displays, searches, and edits Julia source code from the Julia command line.

It is designed for interactive source navigation and small, reviewable source edits. Edits must be displayed before they can be applied, and CodeEdit.jl is intended to be used together with version control.

```@contents
Pages = [
    "getting-started.md",
    "editing.md",
    "searching-errors.md",
    "api.md",
]
Depth = 2
```

## What CodeEdit.jl works with

CodeEdit.jl represents source locations with [`Handle`](@ref)s. A handle points to one parsed block of a file.

For Julia files, blocks are top-level syntactic units such as functions, types, macros, constants, assignments, imports, exports, and includes. Attached docstrings are kept with the following block.

For non-Julia files, blocks are split like paragraphs using blank lines.

## Basic example

```@setup index
using CodeEdit

dir = mktempdir()
cd(dir)

write("foo.jl", """
function foo(x)
    x + 1
end
""")
```

```@repl index
h = Handle("foo.jl", 2)
replacement = replace(string(h), "x + 1" => "x + 2");
edit = Replace(h, replacement);
display(edit)
apply!(edit)
read("foo.jl", String)
```

If Revise.jl is loaded, CodeEdit.jl asks Revise to revise after a successful edit, so changed method definitions usually take effect immediately.

## Safety model

CodeEdit.jl includes several safety checks:

- edits must be displayed before they can be applied;
- Julia files are reparsed before an edit is applied;
- handles track line-number changes caused by other edits where possible;
- file moves and deletions reject symlink paths;
- combined edits are planned and validated as a unit.

There is no undo operation. Use git or another version-control system.
