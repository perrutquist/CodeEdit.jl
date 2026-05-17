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

Editing in CodeEdit.jl separates description from execution: first construct an edit value, then choose how to apply it.

```text
Handle -> Edit -> Displayed plan -> Apply -> Commit
```

Edits are values that subtype [`AbstractEdit`](@ref). Constructing an edit does not modify files; it only describes an intended change to one or more handles or paths.

The standard workflow uses [`VersionControl`](@ref) to apply the edit, stage the affected paths, and create a git commit. If `require_view=true`, displaying, printing, or stringifying an edit records the exact plan that was shown. [`apply!`](@ref) replans the edit and refuses to apply it if the current plan differs from the displayed plan.

In doctest examples, omitting the semicolon from the `edit = ...` line displays the edit and marks it as displayed. Calling `display(edit)` has the same effect.


```jldoctest editing
julia> repo = VersionControl("examples"; require_view=true)
GitVersionControl("examples"; require_view=true)

```

## Choosing an edit operation

Most edits correspond to one of the following operations:

- replace an existing block with [`Replace`](@ref);
- insert code near an existing block with [`InsertBefore`](@ref) or [`InsertAfter`](@ref);
- append code with [`eof_handle`](@ref) and [`InsertBefore`](@ref): the EOF handle is a zero-width anchor at the end of the file;
- delete a block with [`Delete`](@ref);
- create, move, or delete whole files;
- group related edits with [`Combine`](@ref).

The sections below follow that progression.

## Replacing a block

A replacement edit changes exactly the block referenced by a handle. This is usually the safest way to update a function, because the planned diff is limited to the selected block.

```jldoctest editing
julia> h = Handle("examples/DemoPackage.jl", 14)
# examples/DemoPackage.jl 13 - 15:
function increment(x)
    return x + 1
end

julia> new_code = replace(string(h), "x + 1" => "x + 2");

julia> edit = Replace(h, new_code)
Edit modifies examples/DemoPackage.jl:
14c14
<     return x + 1
---
>     return x + 2

julia> apply!(repo, edit, "Change increment")
Applied: 1 file changed, commit 0000000

```

## Inserting code

Insertion edits are useful when a nearby block provides a stable anchor point.

Insert before a block:

```jldoctest editing
julia> h = Handle("examples/DemoPackage.jl", 14)
# examples/DemoPackage.jl 13 - 15:
function increment(x)
    return x + 2
end

julia> edit = InsertBefore(h, raw"""
       const SCALE = 2
       
       """)
Edit modifies examples/DemoPackage.jl:
12c13,14
---
> const SCALE = 2
>

julia> apply!(repo, edit, "Add scale constant")
Applied: 1 file changed, commit 0000000

```

Insert after a block:

```jldoctest editing
julia> h = Handle("examples/DemoPackage.jl", 16)
# examples/DemoPackage.jl 15 - 17:
function increment(x)
    return x + 2
end

julia> edit = InsertAfter(h, raw"""
       
       function scaled_increment(x)
           return increment(x) * SCALE
       end
       """)
Edit modifies examples/DemoPackage.jl:
17c18,21
---
> function scaled_increment(x)
>     return increment(x) * SCALE
> end
>

julia> apply!(repo, edit, "Add scaled_increment")
Applied: 1 file changed, commit 0000000

```

Use raw string literals such as `raw"""..."""` when writing Julia code as strings. They avoid accidental escaping of backslashes and dollar signs.

Inserted text is used exactly as provided. Include leading or trailing newlines when you want blank lines around the inserted code.

## Deleting code

```jldoctest editing
julia> h = only(search(handles("examples/DemoPackage.jl"), "function obsolete"))
# examples/DemoPackage.jl 27 - 29:
function obsolete()
    return :remove_me
end

julia> edit = Delete(h)
Edit modifies examples/DemoPackage.jl:
27,29c26
< function obsolete()
<     return :remove_me
< end
---

julia> apply!(repo, edit, "Remove obsolete function")
Applied: 1 file changed, commit 0000000

```

Deleting an EOF handle has no effect and is usually not useful.

## Creating, moving, and deleting files

```jldoctest editing
julia> edit = CreateFile("examples/generated.jl", raw"""
       function generated_value()
           return :ok
       end
       """)
Edit creates examples/generated.jl:
0c1,3
---
> function generated_value()
>     return :ok
> end

julia> apply!(repo, edit, "Add generated file")
Applied: 1 file changed, commit 0000000

```

```jldoctest editing
julia> edit = MoveFile("examples/generated.jl", "examples/generated-renamed.jl")
Edit moves examples/generated.jl -> examples/generated-renamed.jl

julia> apply!(repo, edit, "Rename generated file")
Applied: 1 file changed, commit 0000000

```

```jldoctest editing
julia> edit = DeleteFile("examples/generated-renamed.jl")
Edit deletes examples/generated-renamed.jl

julia> apply!(repo, edit, "Remove generated file")
Applied: 1 file changed, commit 0000000

```

## Combining edits

Use [`Combine`](@ref), or the `*` shorthand, when multiple edits are part of one logical change and should be planned together:

```jldoctest editing
julia> source = only(search(handles("examples/DemoPackage.jl"), "function old_function_name"))
# examples/DemoPackage.jl 23 - 25:
function old_function_name()
    return foo(1)
end

julia> destination = eof_handle("examples/notes.txt")
# examples/notes.txt EOF:

julia> edit = Combine(
           InsertBefore(destination, "\nMoved selected source:\n\n" * string(source)),
           Delete(source),
       )
Edit modifies examples/DemoPackage.jl:
23,25c22
< function old_function_name()
<     return foo(1)
< end
---
Edit modifies examples/notes.txt:
3c4,9
---
>
> Moved selected source:
>
> function old_function_name()
>     return foo(1)
> end

julia> apply!(repo, edit, "Move selected source to notes")
Applied: 2 files changed, commit 0000000

```

Equivalent shorthand:

```jldoctest editing
julia> h = only(search(handles("examples/DemoPackage.jl"), "function increment"))
# examples/DemoPackage.jl 15 - 17:
function increment(x)
    return x + 2
end

julia> edit = InsertAfter(h, raw"""
       
       function bounded_increment(x)
           return min(increment(x), DEFAULT_LIMIT)
       end
       """) * InsertBefore(eof_handle("examples/notes.txt"), "\nAdded bounded_increment to DemoPackage.jl\n")
Edit modifies examples/DemoPackage.jl:
17c18,21
---
> function bounded_increment(x)
>     return min(increment(x), DEFAULT_LIMIT)
> end
>
Edit modifies examples/notes.txt:
9c10,11
---
>
> Added bounded_increment to DemoPackage.jl

julia> apply!(repo, edit, "Add bounded_increment and update notes")
Applied: 2 files changed, commit 0000000

```

Combined edits are validated after the full combined result is planned. Intermediate states may therefore be invalid Julia syntax, provided the final result is valid.

Planning and validation are all-or-nothing. Applying a combined edit that touches multiple files is still best-effort at the filesystem level: if a later filesystem operation fails, earlier operations may already have been applied. Use version control so changes can be reviewed and recovered.

## Applying edits without version control

For scratch files, generated files, or other changes that should not create a commit, pass an explicit [`NoVersionControl`](@ref) specification.

[`NoVersionControl`](@ref) makes uncommitted edits explicit at the call site.

```jldoctest editing
julia> write("scratch-note.txt", "status = old\n")
13

julia> h = Handle("scratch-note.txt", 1; parse_as=:text)
# scratch-note.txt 1 - 1:
status = old

julia> edit = Replace(h, "status = new\n")
Edit modifies scratch-note.txt:
1c1
< status = old
---
> status = new

julia> apply!(NoVersionControl(require_view=true), edit)
Applied: 1 file changed

```
