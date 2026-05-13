# Editing code

Edits are represented as values that subtype [`AbstractEdit`](@ref). Construct an edit, optionally display it to review the diff, then apply it through an explicit version-control specification.

The standard workflow uses [`VersionControl`](@ref) to apply the edit, stage the affected paths, and create a git commit. If you set `require_view=true`, displaying, printing, or stringifying an edit records the exact plan that was shown. [`apply!`](@ref) replans the edit and refuses to apply it if the new plan does not match the displayed plan. In REPL examples, leaving the semicolon off the `edit = ...` line displays the edit and marks it as displayed; calling `display(edit)` works too.

Use [`displayed!`](@ref) only when you intentionally want to mark an edit as reviewed without printing the diff.

```@setup editing
using CodeEdit

rm("examples"; recursive=true, force=true)
mkpath("examples")

project_file = "examples/ProjectCode.jl"
notes_file = "examples/notes.txt"

write(project_file, """
module ProjectCode

const DEFAULT_LIMIT = 10

function foo(x)
    return x + 1
end

function helper(x)
    return foo(x) * 2
end

function obsolete()
    return :remove_me
end

end
""")

write(notes_file, """
First note.

Second note.
""")

run(`git init examples`)
run(`git -C examples config user.email docs@example.com`)
run(`git -C examples config user.name "CodeEdit Docs"`)
run(`git -C examples add .`)
run(`git -C examples commit -m "Initial editing examples"`)

sleep(1.1)
```

```@repl editing
repo = VersionControl("examples"; require_view=true)
```

## Replacing a block

```@repl editing
h = Handle("examples/ProjectCode.jl", 6)
new_code = replace(string(h), "x + 1" => "x + 2");
edit = Replace(h, new_code)
apply!(repo, edit, "Change foo increment")
```

## Inserting code

Insert before a block:

```@repl editing
h = Handle("examples/ProjectCode.jl", 6)
edit = InsertBefore(h, raw"""
const SCALE = 2

""")
apply!(repo, edit, "Add scale constant")
```

Insert after a block:

```@repl editing
h = Handle("examples/ProjectCode.jl", 6)
edit = InsertAfter(h, raw"""

function bar(x)
    return foo(x) + SCALE
end
""")
apply!(repo, edit, "Add bar")
```

Use raw string literals such as `raw"""..."""` when writing Julia code as strings. They avoid accidental escaping of backslashes and dollar signs.

## Deleting code

```@repl editing
h = Handle("examples/ProjectCode.jl", 14)
edit = Delete(h)
apply!(repo, edit, "Remove obsolete function")
```

EOF handles are unaffected by [`Delete`](@ref).

## Creating, moving, and deleting files

```@repl editing
edit = CreateFile("examples/generated.jl", raw"""
function generated_value()
    return :ok
end
""")
apply!(repo, edit, "Add generated file")
```

```@repl editing
edit = MoveFile("examples/generated.jl", "examples/generated-renamed.jl")
apply!(repo, edit, "Rename generated file")
```

```@repl editing
edit = DeleteFile("examples/generated-renamed.jl")
apply!(repo, edit, "Remove generated file")
```

## Combining edits

Use [`Combine`](@ref), or the `*` shorthand, when multiple edits should be planned together:

```@repl editing
source = Handle("examples/ProjectCode.jl", 10)
destination = eof_handle("examples/notes.txt")
edit = Combine(
    InsertBefore(destination, "\nMoved helper source:\n\n" * string(source)),
    Delete(source),
)
apply!(repo, edit, "Move helper source to notes")
```

Equivalent shorthand:

```@repl editing
h = Handle("examples/ProjectCode.jl", 6)
edit = InsertAfter(h, raw"""

function baz(x)
    return foo(x) - 1
end
""") * InsertBefore(eof_handle("examples/notes.txt"), "\nAdded baz to ProjectCode.jl\n")
apply!(repo, edit, "Add baz and update notes")
```

Combined edits are validated after the full combined result is planned. This allows intermediate states to be temporarily invalid Julia syntax.

Planning and validation are all-or-nothing, but applying a combined edit that touches multiple files is best-effort at the filesystem level. If a later filesystem operation fails, earlier operations may already have been applied. Use version control so changes can be reviewed and recovered.

## Applying edits without version control

For scratch files, generated files, or other changes that should not create a commit, pass an explicit [`NoVersionControl`](@ref) specification.

```@repl editing
write("scratch-note.txt", "status = old\n")
h = Handle("scratch-note.txt", 1; parse_as=:text)
edit = Replace(h, "status = new\n")
apply!(NoVersionControl(require_view=true), edit)
```

## Marking an edit as displayed

If you intentionally need to bypass printing the diff while `require_view=true`, use [`displayed!`](@ref):

```@repl editing
h = Handle("scratch-note.txt", 1; parse_as=:text)
edit = Replace(h, "status = reviewed\n");
displayed!(edit, true);
apply!(NoVersionControl(require_view=true), edit)
```

Use this with caution.
