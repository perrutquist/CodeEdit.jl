# CodeEdit.jl

CodeEdit.jl locates, displays, searches, and edits Julia source code from the Julia command line.

It is designed for interactive source navigation and small, reviewable source edits. The standard workflow applies an edit through git and records the result as a commit.

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

run(`git init examples`)
run(`git -C examples config user.email docs@example.com`)
run(`git -C examples config user.name "CodeEdit Docs"`)
run(`git -C examples add .`)
run(`git -C examples commit -m "Initial example files"`)

sleep(1.1)
```

```@repl index
repo = VersionControl("examples"; require_view=true)
h = Handle("examples/foo.jl", 2)
replacement = replace(string(h), "x + 1" => "x + 2");
edit = Replace(h, replacement)
apply!(repo, edit, "Change foo increment")
read("examples/foo.jl", String)
```

If Revise.jl is loaded, CodeEdit.jl asks Revise to revise after a successful edit, so changed method definitions usually take effect immediately.

## Safety model

CodeEdit.jl includes several safety checks:

- the standard workflow stages affected paths and records the edit as a git commit;
- git-backed edits require affected files to be versioned by default;
- `require_view=true` records the exact displayed plan and rejects application if replanning changes it;
- Julia files are reparsed before an edit is applied;
- handles track line-number changes caused by other edits where possible;
- file moves and deletions reject symlink paths;
- combined edits are planned and validated as a unit.

Applying a combined edit that touches multiple files is best-effort at the filesystem level, so a later filesystem failure can still leave earlier file operations applied. Use git or another version-control system so changes can be reviewed and recovered.
