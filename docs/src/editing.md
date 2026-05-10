# Editing code

Edits are represented as values that subtype [`AbstractEdit`](@ref). Construct an edit, display it to review the diff, then apply it.

Displaying, printing, or stringifying an edit records the exact plan that was shown. [`apply!`](@ref) replans the edit and refuses to apply it if the new plan does not match the displayed plan. In REPL examples, leaving the semicolon off the `edit = ...` line displays the edit and marks it as displayed; calling `display(edit)` works too.

Use [`displayed!`](@ref) only when you intentionally want to mark an edit as reviewed without printing the diff.

```@setup editing
using CodeEdit

rm("examples"; recursive=true, force=true)
mkpath("examples")
replace_example = "examples/replace.jl"
insert_before_example = "examples/insert-before.jl"
insert_after_example = "examples/insert-after.jl"
delete_example = "examples/delete.jl"
old_name = "examples/old-name.jl"
new_name = "examples/new-name.jl"
unused_file = "examples/unused.jl"
new_file = "examples/new-file.jl"
source_file = "examples/source.jl"
destination_file = "examples/destination.jl"
source_shorthand_file = "examples/source-shorthand.jl"
destination_shorthand_file = "examples/destination-shorthand.jl"
nodisplay_example = "examples/no-display.jl"

write(replace_example, """
function foo(x)
    x + 1
end
""")

write(insert_before_example, """
function foo(x)
    x + 1
end
""")

write(insert_after_example, """
function foo(x)
    x + 1
end
""")

write(delete_example, """
function helper(x)
    return x + 1
end

function obsolete()
    return :remove_me
end
""")

write(old_name, "old_value() = 1\n")
write(unused_file, "unused() = true\n")

write(source_file, """
function source()
    return :moved
end
""")
write(destination_file, "")

write(source_shorthand_file, """
function source_shorthand()
    return :moved
end
""")
write(destination_shorthand_file, "")

write(nodisplay_example, "status() = :old\n")

sleep(1.1)
```

## Replacing a block

```@repl editing
h = Handle("examples/replace.jl", 2)
new_code = replace(string(h), "x + 1" => "x + 2");
edit = Replace(h, new_code)
apply!(edit)
```

## Inserting code

Insert before a block:

```@repl editing
h = Handle("examples/insert-before.jl", 1)
edit = InsertBefore(h, raw"""
const DEFAULT_LIMIT = 10

""")
apply!(edit)
```

Insert after a block:

```@repl editing
h = Handle("examples/insert-after.jl", 1)
edit = InsertAfter(h, raw"""

function helper(x)
    return x + 1
end
""")
apply!(edit)
```

Use raw string literals such as `raw"""..."""` when writing Julia code as strings. They avoid accidental escaping of backslashes and dollar signs.

## Deleting code

```@repl editing
h = Handle("examples/delete.jl", 5)
edit = Delete(h)
apply!(edit)
```

EOF handles are unaffected by [`Delete`](@ref).

## Creating, moving, and deleting files

```@repl editing
edit = CreateFile("examples/new-file.jl", raw"""
function new_file_function()
    return :ok
end
""")
apply!(edit)
```

```@repl editing
edit = MoveFile("examples/old-name.jl", "examples/new-name.jl")
apply!(edit)
```

```@repl editing
edit = DeleteFile("examples/unused.jl")
apply!(edit)
```

## Combining edits

Use [`Combine`](@ref), or the `*` shorthand, when multiple edits should be planned together:

```@repl editing
source = Handle("examples/source.jl", 1)
destination = eof_handle("examples/destination.jl")
edit = Combine(
    InsertBefore(destination, string(source)),
    Delete(source),
)
apply!(edit)
```

Equivalent shorthand:

```@repl editing
source = Handle("examples/source-shorthand.jl", 1)
destination = eof_handle("examples/destination-shorthand.jl")
edit = InsertBefore(destination, string(source)) * Delete(source)
```

Combined edits are validated after the full combined result is planned. This allows intermediate states to be temporarily invalid Julia syntax.

Planning and validation are all-or-nothing, but applying a combined edit that touches multiple files is best-effort at the filesystem level. If a later filesystem operation fails, earlier operations may already have been applied. Use version control so changes can be reviewed and recovered.

## Applying edits without display

By default, [`apply!`](@ref) refuses to apply an edit until it has been displayed. This is intentional.

If you intentionally need to bypass display, use [`displayed!`](@ref):

```@repl editing
h = Handle("examples/no-display.jl", 1)
edit = Replace(h, replace(string(h), ":old" => ":new"));
displayed!(edit, true);
apply!(edit)
```

Use this with caution.
