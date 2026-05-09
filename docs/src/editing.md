# Editing code

Edits are represented as values that subtype [`AbstractEdit`](@ref). Construct an edit, display it to review the diff, then apply it. In REPL examples, leaving the semicolon off the `edit = ...` line displays the edit and marks it as displayed; calling `display(edit)` works too.

```@setup editing
using CodeEdit

dir = mktempdir()
replace_example = joinpath(dir, "replace_example.jl")
insert_before_example = joinpath(dir, "insert_before_example.jl")
insert_after_example = joinpath(dir, "insert_after_example.jl")
delete_example = joinpath(dir, "delete_example.jl")
old_name = joinpath(dir, "old_name.jl")
new_name = joinpath(dir, "new_name.jl")
unused_file = joinpath(dir, "unused_file.jl")
new_file = joinpath(dir, "new_file.jl")
source_file = joinpath(dir, "source.jl")
destination_file = joinpath(dir, "destination.jl")
source_shorthand_file = joinpath(dir, "source_shorthand.jl")
destination_shorthand_file = joinpath(dir, "destination_shorthand.jl")
nodisplay_example = joinpath(dir, "nodisplay_example.jl")

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
```

## Replacing a block

```@repl editing
h = Handle(replace_example, 2)
new_code = replace(string(h), "x + 1" => "x + 2");
edit = Replace(h, new_code)
apply!(edit)
```

## Inserting code

Insert before a block:

```@repl editing
h = Handle(insert_before_example, 1)
edit = InsertBefore(h, raw"""
const DEFAULT_LIMIT = 10

""")
apply!(edit)
```

Insert after a block:

```@repl editing
h = Handle(insert_after_example, 1)
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
h = Handle(delete_example, 5)
edit = Delete(h)
apply!(edit)
```

EOF handles are unaffected by [`Delete`](@ref).

## Creating, moving, and deleting files

```@repl editing
edit = CreateFile(new_file, raw"""
function new_file_function()
    return :ok
end
""");
display(edit)
apply!(edit)
```

```@repl editing
edit = MoveFile(old_name, new_name)
apply!(edit)
```

```@repl editing
edit = DeleteFile(unused_file)
apply!(edit)
```

## Combining edits

Use [`Combine`](@ref), or the `*` shorthand, when multiple edits should be planned together:

```@repl editing
source = Handle(source_file, 1)
destination = eof_handle(destination_file)
edit = Combine(
    InsertBefore(destination, string(source)),
    Delete(source),
)
apply!(edit)
```

Equivalent shorthand:

```@repl editing
source = Handle(source_shorthand_file, 1)
destination = eof_handle(destination_shorthand_file)
edit = InsertBefore(destination, string(source)) * Delete(source)
```

Combined edits are validated after the full combined result is planned. This allows intermediate states to be temporarily invalid Julia syntax.

## Applying edits without display

By default, [`apply!`](@ref) refuses to apply an edit until it has been displayed. This is intentional.

If you intentionally need to bypass display, use [`displayed!`](@ref):

```@repl editing
h = Handle(nodisplay_example, 1)
edit = Replace(h, replace(string(h), ":old" => ":new"));
displayed!(edit, true);
apply!(edit)
```

Use this with caution.
