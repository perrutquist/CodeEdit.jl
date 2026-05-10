# CodeEdit.jl

CodeEdit.jl locates, displays, searches, and edits Julia source code from the Julia command line.

It is designed for interactive source navigation and small, reviewable source edits. Edits must be displayed before they can be applied, and CodeEdit.jl is intended to be used together with version control.

- [Getting started](getting-started.md)
- [Blocks and handles](concepts.md)
- [Editing code](editing.md)
- [Finding errors from stacktraces](searching-errors.md)
- [API reference](api.md)

## What CodeEdit.jl works with

CodeEdit.jl represents source locations with [`Handle`](@ref)s. A handle points to one parsed block of a file. See [Blocks and handles](concepts.md) for details.

For Julia files, blocks are top-level syntactic units such as functions, types, macros, constants, assignments, imports, exports, and includes. Attached docstrings are kept with the following block.

For non-Julia files, blocks are split like paragraphs using blank lines.

## Basic example

```@setup index
using CodeEdit

rm("examples"; recursive=true, force=true)
mkpath("examples")

write("examples/foo.jl", """
function foo(x)
    x + 1
end
""")

sleep(1.1)
```

```@repl index
h = Handle("examples/foo.jl", 2)
replacement = replace(string(h), "x + 1" => "x + 2");
edit = Replace(h, replacement)
apply!(edit)
read("examples/foo.jl", String)
```

If Revise.jl is loaded, CodeEdit.jl asks Revise to revise after a successful edit, so changed method definitions usually take effect immediately.

## Safety model

CodeEdit.jl includes several safety checks:

- edits must be displayed before they can be applied;
- displaying, printing, or stringifying an edit records the displayed plan;
- edits are replanned before application and rejected if the plan changed;
- Julia files are reparsed before an edit is applied;
- handles track line-number changes caused by other edits where possible;
- file moves and deletions reject symlink paths;
- combined edits are planned and validated as a unit.

Applying a combined edit that touches multiple files is best-effort at the filesystem level, so a later filesystem failure can still leave earlier file operations applied. There is no undo operation. Use git or another version-control system.
