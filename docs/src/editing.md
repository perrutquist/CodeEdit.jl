# Editing code

Edits are represented as values that subtype [`AbstractEdit`](@ref). Construct an edit, display it to review the diff, then apply it.

```@setup editing
using CodeEdit

dir = mktempdir()
cd(dir)

write("replace_example.jl", """
function foo(x)
    x + 1
end
""")

write("insert_before_example.jl", """
function foo(x)
    x + 1
end
""")

write("insert_after_example.jl", """
function foo(x)
    x + 1
end
""")

write("delete_example.jl", """
function helper(x)
    return x + 1
end

function obsolete()
    return :remove_me
end
""")

write("old_name.jl", "old_value() = 1\n")
write("unused_file.jl", "unused() = true\n")

write("source.jl", """
function source()
    return :moved
end
""")
write("destination.jl", "")

write("source_shorthand.jl", """
function source_shorthand()
    return :moved
end
""")
write("destination_shorthand.jl", "")

write("nodisplay_example.jl", "status() = :old\n")
```

## Replacing a block

```@repl editing
h = Handle("replace_example.jl", 2)
new_code = replace(string(h), "x + 1" => "x + 2");
edit = Replace(h, new_code);
display(edit)
apply!(edit)
```

## Inserting code

Insert before a block:

```@repl editing
h = Handle("insert_before_example.jl", 1)
edit = InsertBefore(h, raw"""
const DEFAULT_LIMIT = 10

""");
display(edit)
apply!(edit)
```

Insert after a block:

```@repl editing
h = Handle("insert_after_example.jl", 1)
edit = InsertAfter(h, raw"""

function helper(x)
    return x + 1
end
""");
display(edit)
apply!(edit)
```

Use raw string literals such as `raw"""..."""` when writing Julia code as strings. They avoid accidental escaping of backslashes and dollar signs.

## Deleting code

```@repl editing
h = Handle("delete_example.jl", 5)
edit = Delete(h);
display(edit)
apply!(edit)
```

EOF handles are unaffected by [`Delete`](@ref).

## Creating, moving, and deleting files

```@repl editing
edit = CreateFile("new_file.jl", raw"""
function new_file_function()
    return :ok
end
""");
display(edit)
apply!(edit)
```

```@repl editing
edit = MoveFile("old_name.jl", "new_name.jl");
display(edit)
apply!(edit)
```

```@repl editing
edit = DeleteFile("unused_file.jl");
display(edit)
apply!(edit)
```

## Combining edits

Use [`Combine`](@ref), or the `*` shorthand, when multiple edits should be planned together:

```@repl editing
source = Handle("source.jl", 1)
destination = eof_handle("destination.jl")
edit = Combine(
    InsertBefore(destination, string(source)),
    Delete(source),
);
display(edit)
apply!(edit)
```

Equivalent shorthand:

```@repl editing
source = Handle("source_shorthand.jl", 1)
destination = eof_handle("destination_shorthand.jl")
edit = InsertBefore(destination, string(source)) * Delete(source);
display(edit)
```

Combined edits are validated after the full combined result is planned. This allows intermediate states to be temporarily invalid Julia syntax.

## Applying edits without display

By default, [`apply!`](@ref) refuses to apply an edit until it has been displayed. This is intentional.

If you intentionally need to bypass display, use [`displayed!`](@ref):

```@repl editing
h = Handle("nodisplay_example.jl", 1)
edit = Replace(h, replace(string(h), ":old" => ":new"));
displayed!(edit, true);
apply!(edit)
```

Use this with caution.
