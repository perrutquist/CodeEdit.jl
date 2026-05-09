# Editing code

Edits are represented as values that subtype [`AbstractEdit`](@ref). Construct an edit, display it to review the diff, then apply it.

## Replacing a block

```julia
h = Handle("src/example.jl", 4)

new_code = replace(string(h), "x + 1" => "x + 2")
edit = Replace(h, new_code)

display(edit)
apply!(edit)
```

## Inserting code

Insert before a block:

```julia
h = Handle("src/example.jl", 1)

edit = InsertBefore(h, raw"""
const DEFAULT_LIMIT = 10

""")

display(edit)
apply!(edit)
```

Insert after a block:

```julia
h = Handle("src/example.jl", 1)

edit = InsertAfter(h, raw"""

function helper(x)
    return x + 1
end
""")

display(edit)
apply!(edit)
```

Use raw string literals such as `raw"""..."""` when writing Julia code as strings. They avoid accidental escaping of backslashes and dollar signs.

## Deleting code

```julia
h = Handle("src/example.jl", 12)

edit = Delete(h)
display(edit)
apply!(edit)
```

EOF handles are unaffected by [`Delete`](@ref).

## Creating, moving, and deleting files

```julia
edit = CreateFile("src/new_file.jl", raw"""
function new_file_function()
    return :ok
end
""")

display(edit)
apply!(edit)
```

```julia
edit = MoveFile("src/old_name.jl", "src/new_name.jl")
display(edit)
apply!(edit)
```

```julia
edit = DeleteFile("src/unused_file.jl")
display(edit)
apply!(edit)
```

## Combining edits

Use [`Combine`](@ref), or the `*` shorthand, when multiple edits should be planned together:

```julia
source = Handle("src/source.jl", 20)
destination = eof_handle("src/destination.jl")

edit = Combine(
    InsertBefore(destination, string(source)),
    Delete(source),
)

display(edit)
apply!(edit)
```

Equivalent shorthand:

```julia
edit = InsertBefore(destination, string(source)) * Delete(source)
```

Combined edits are validated after the full combined result is planned. This allows intermediate states to be temporarily invalid Julia syntax.

## Applying edits without display

By default, [`apply!`](@ref) refuses to apply an edit until it has been displayed. This is intentional.

If you intentionally need to bypass display, use [`displayed!`](@ref):

```julia
displayed!(edit, true)
apply!(edit)
```

Use this with caution.
