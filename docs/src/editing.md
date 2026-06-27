```@meta
DocTestSetup = quote
    include(joinpath($(@__DIR__), "meta_setup.jl"))
    if !@isdefined(_editing_examples_ready)
        ensure_examples!()
        _editing_examples_ready = true
    end
end
```

# Editing code

Patch constructors create immutable patch values. Use [`apply!`](@ref) or [`commit!`](@ref) to write a patch.

```text
workspace -> blocks -> patches -> apply!/commit!
```

The standard workflow infers git from the touched files, stages the affected paths, and creates a commit when you provide a commit message. See [Safety and version control](safety.md) for review requirements, validation, and dirty-file behavior.

In doctest examples, omitting the semicolon from the `p = ...` line displays the patch and marks it as reviewed. Calling `display(p)` has the same effect.

## Replacing source

A replacement patch changes exactly the selected block. This is usually the safest way to update a function, because the planned diff is limited to the chosen block.

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function increment"))
# examples/DemoPackage.jl 13 - 15:
function increment(x)
    return x + 1
end

julia> p = replace(b, "x + 1" => "x + 2")
Patch modifies examples/DemoPackage.jl:
14c14
<     return x + 1
---
>     return x + 2
```

If the second argument is a string rather than replacement pairs, the whole block is replaced:

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function increment"));

julia> p = replace(b, raw"""
       function increment(x)
       return x + 10
       end
       """)
Patch modifies examples/DemoPackage.jl:
14c14
<     return x + 1
---
> return x + 10
```

You can also make several text replacements within the same block:

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function foo"));

julia> p = replace(b,
           "y = helper(x)" => "y = helper(abs(x))",
           "z = y * 2" => "z = y * DEFAULT_LIMIT",
       )
Patch modifies examples/DemoPackage.jl:
8,9c8,9
<     y = helper(x)
<     z = y * 2
---
>     y = helper(abs(x))
>     z = y * DEFAULT_LIMIT
```

Replacing across many matching blocks returns one combined patch:

```jldoctest editing
julia> ws = workspace("examples");

julia> p = replace(find(ws, "old_function_name"), "old_function_name" => "new_function_name")
Patch modifies examples/DemoPackage.jl:
17c17
< function old_function_name()
---
> function new_function_name()
```

## Inserting source

Insertion patches are useful when a nearby block provides a stable anchor point.

Insert before a block:

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function increment"));

julia> p = insert_before(b, raw"""
       const SCALE = 2
       
       """)
Patch modifies examples/DemoPackage.jl:
12c13,14
---
> const SCALE = 2
>
```

Insert after a block:

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function increment"));

julia> p = insert_after(b, raw"""
       
       function scaled_increment(x)
       return increment(x) * SCALE
       end
       """)
Patch modifies examples/DemoPackage.jl:
16c17,20
---
> function scaled_increment(x)
> return increment(x) * SCALE
> end
>
```

Use raw string literals such as `raw"""..."""` when writing Julia code as strings. Inserted text is used exactly as provided, so include leading or trailing newlines when you want blank lines around the inserted code.

## Appending and prepending

Use [`append_to`](@ref) or [`prepend_to`](@ref) for file-level insertion without manually selecting an EOF block.

```jldoctest editing
julia> p = append_to("examples/helpers.jl", raw"""
       
       another_helper(x) = helper(x) * 2
       """)
Patch modifies examples/helpers.jl:
1c2,3
---
>
> another_helper(x) = helper(x) * 2
```

```jldoctest editing
julia> p = prepend_to("examples/helpers.jl", "# Helper functions\n\n")
Patch modifies examples/helpers.jl:
0c1,2
---
> # Helper functions
>
```

## Deleting source

Deleting a block produces a patch that removes that block from the file:

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function obsolete"))
# examples/DemoPackage.jl 21 - 23:
function obsolete()
    return :remove_me
end

julia> p = delete(b)
Patch modifies examples/DemoPackage.jl:
21,23c20
< function obsolete()
<     return :remove_me
< end
---
```

Deleting multiple matching blocks as one combined patch is also supported:

```jldoctest editing
julia> ws = workspace("examples");

julia> p = delete(find(ws, "return :remove_me"))
Patch modifies examples/DemoPackage.jl:
21,23c20
< function obsolete()
<     return :remove_me
< end
---
```

## Creating, moving, and deleting files

Whole-file operations use explicit names that do not conflict with Base filesystem functions:

```jldoctest editing
julia> p = create_file("examples/generated.jl", raw"""
       function generated_value()
       return :ok
       end
       """)
Patch creates examples/generated.jl:
0c1,3
---
> function generated_value()
> return :ok
> end
```

```jldoctest editing
julia> p = move_file("examples/generated.jl", "examples/generated-renamed.jl")
Validation errors:
- file does not exist: /Users/rutquist/Documents/Julia/CodeEdit/docs/examples/generated.jl
```

```jldoctest editing
julia> p = delete_file("examples/generated-renamed.jl")
Validation errors:
- file does not exist: /Users/rutquist/Documents/Julia/CodeEdit/docs/examples/generated-renamed.jl
```

## Combining patches

Use `+` when multiple patches are part of one logical change and should be planned together:

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function increment"));

julia> p = replace(b, "x + 1" => "x + 2") +
           insert_after(b, raw"""
           
           function decrement(x)
           return x - 1
           end
           """)
Patch modifies examples/DemoPackage.jl:
14c14,18
<     return x + 1
---
>     return x + 2
> end
>
> function decrement(x)
> return x - 1
```

A function form is available as well:

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function increment"));

julia> p = patch(
           replace(b, "x + 1" => "x + 2"),
           insert_after(b, "\nextra(x) = x\n"),
       )
Patch modifies examples/DemoPackage.jl:
14,15c14,17
<     return x + 1
< end
---
>     return x + 2
> end
>
> extra(x) = x
```

Combined patches are validated after the final combined result is planned. Intermediate states may therefore be invalid Julia syntax, provided the final result is valid.

## Applying patches

A patch becomes real only when you apply it:

```jldoctest editing
julia> ws = workspace("examples");

julia> b = only(find(ws, "function increment"));

julia> p = replace(b, "x + 1" => "x + 2")
Patch modifies examples/DemoPackage.jl:
14c14
<     return x + 1
---
>     return x + 2

julia> commit!(p, "Change increment")
Applied: 1 file changed, commit 67decaf
```

[`commit!`](@ref) is the obvious git-backed spelling. It is equivalent to `apply!(p, msg; git=:required)`.

## Applying without git

For scratch files, generated files, or other changes that should not create a commit, pass `git=false` to [`apply!`](@ref):

```jldoctest editing
julia> write("scratch-note.txt", "status = old\n")
13

julia> b = block("scratch-note.txt:1"; as=:text)
# scratch-note.txt 1 - 1:
status = old

julia> p = replace(b, "old" => "new")
Patch modifies scratch-note.txt:
1c1
< status = old
---
> status = new

julia> apply!(p; git=false)
Applied: 1 file changed
```
