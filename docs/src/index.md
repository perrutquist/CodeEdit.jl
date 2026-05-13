# CodeEdit.jl

CodeEdit.jl helps you make small, reviewable source edits from the Julia command line.

Instead of editing raw line ranges directly, you work with handles to parsed source blocks. You can inspect a block, build an edit value, review the planned diff, and then apply the change through git or an explicit no-version-control mode.

- [Getting started](getting-started.md)
- [Blocks and handles](concepts.md)
- [Editing code](editing.md)
- [Safety and version control](safety.md)
- [Finding errors from stacktraces](searching-errors.md)
- [API reference](api.md)

## What CodeEdit.jl works with

CodeEdit.jl represents source locations with [`Handle`](@ref)s. A handle points to one parsed block of a file. See [Blocks and handles](concepts.md) for details.

For Julia files, blocks are top-level syntactic units such as functions, types, macros, constants, assignments, imports, exports, and includes. Attached docstrings are kept with the following block.

For non-Julia files, blocks are split like paragraphs using blank lines.

## Basic workflow

The central workflow is:

```text
Handle -> Edit -> Displayed plan -> Apply -> Commit
```

The example below creates a tiny git repository, changes one function, applies the edit, and reads the file back from disk.

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

CodeEdit.jl separates planning from applying. Creating an edit does not modify files. Displaying an edit shows the planned change, and `require_view=true` makes [`apply!`](@ref) verify that the displayed plan is still current before writing anything.

The standard workflow applies edits through git and records each successful change as a commit. See [Safety and version control](safety.md) for the full model.
