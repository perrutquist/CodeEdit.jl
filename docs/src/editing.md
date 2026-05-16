# Editing code

Editing in CodeEdit.jl separates description from execution: first construct an edit value, then choose how to apply it.

```text
Handle -> Edit -> Displayed plan -> Apply -> Commit
```

Edits are values that subtype [`AbstractEdit`](@ref). Constructing an edit does not modify files; it only describes an intended change to one or more handles or paths.

The standard workflow uses [`VersionControl`](@ref) to apply the edit, stage the affected paths, and create a git commit. If `require_view=true`, displaying, printing, or stringifying an edit records the exact plan that was shown. [`apply!`](@ref) replans the edit and refuses to apply it if the current plan differs from the displayed plan.

In REPL examples, omitting the semicolon from the `edit = ...` line displays the edit and marks it as displayed. Calling `display(edit)` has the same effect.

```@meta
DocTestFilters = [r"/[0-9a-zA-Z/]*/examples", r"main [0-9a-f]*", r"commit [0-9a-f]*"]

DocTestSetup = quote
    using CodeEdit

    if !@isdefined(created_examples)
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

        created_examples = true
    end
end
```

```jldoctest editing
julia> repo = VersionControl("examples"; require_view=true)
GitVersionControl("examples"; require_view=true)

```

## Choosing an edit operation

Most edits correspond to one of the following operations:

- replace an existing block with [`Replace`](@ref);
- insert code near an existing block with [`InsertBefore`](@ref) or [`InsertAfter`](@ref);
- insert code at the end of a file with [`eof_handle`](@ref) and [`InsertBefore`](@ref);
- delete a block with [`Delete`](@ref);
- create, move, or delete whole files;
- group related edits with [`Combine`](@ref).

The sections below follow that progression.

## Replacing a block

A replacement edit changes exactly the block referenced by a handle. This is usually the safest way to update a function, because the planned diff is limited to the selected block.

```jldoctest editing
julia> h = Handle("examples/ProjectCode.jl", 6)
# examples/ProjectCode.jl 5 - 7:
function foo(x)
    return x + 1
end

julia> new_code = replace(string(h), "x + 1" => "x + 2");

julia> edit = Replace(h, new_code)
Edit modifies examples/ProjectCode.jl:
6c6
<     return x + 1
---
>     return x + 2

julia> apply!(repo, edit, "Change foo increment")
[main 96880f1] Change foo increment
 1 file changed, 1 insertion(+), 1 deletion(-)
Applied: 1 file changed, commit 96880f1

```

## Inserting code

Insertion edits are useful when a nearby block provides a stable anchor point.

Insert before a block:

```jldoctest editing
julia> h = Handle("examples/ProjectCode.jl", 6)
# examples/ProjectCode.jl 5 - 7:
function foo(x)
    return x + 2
end

julia> edit = InsertBefore(h, raw"""
       const SCALE = 2
       
       """)
Edit modifies examples/ProjectCode.jl:
4c5,6
---
> const SCALE = 2
>

julia> apply!(repo, edit, "Add scale constant")
[main 46bd4e8] Add scale constant
 1 file changed, 2 insertions(+)
Applied: 1 file changed, commit 46bd4e8

```

Insert after a block:

```jldoctest editing
julia> h = Handle("examples/ProjectCode.jl", 6)
# examples/ProjectCode.jl 7 - 9:
function foo(x)
    return x + 2
end

julia> edit = InsertAfter(h, raw"""
       
       function bar(x)
           return foo(x) + SCALE
       end
       """)
Edit modifies examples/ProjectCode.jl:
10c11,14
---
> function bar(x)
>     return foo(x) + SCALE
> end
>

julia> apply!(repo, edit, "Add bar")
[main b1d84cc] Add bar
 1 file changed, 4 insertions(+)
Applied: 1 file changed, commit b1d84cc

```

Use raw string literals such as `raw"""..."""` when writing Julia code as strings. They avoid accidental escaping of backslashes and dollar signs.

## Deleting code

```jldoctest editing
julia> h = Handle("examples/ProjectCode.jl", 14)
# examples/ProjectCode.jl 15 - 17:
function helper(x)
    return foo(x) * 2
end

julia> edit = Delete(h)
Edit modifies examples/ProjectCode.jl:
15,17c14
< function helper(x)
<     return foo(x) * 2
< end
---

julia> apply!(repo, edit, "Remove obsolete function")
[main f12b975] Remove obsolete function
 1 file changed, 3 deletions(-)
Applied: 1 file changed, commit f12b975

```

EOF handles are unaffected by [`Delete`](@ref).

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
[main bbb6671] Add generated file
 1 file changed, 3 insertions(+)
 create mode 100644 generated.jl
Applied: 1 file changed, commit bbb6671

```

```jldoctest editing
julia> edit = MoveFile("examples/generated.jl", "examples/generated-renamed.jl")
Edit moves examples/generated.jl -> examples/generated-renamed.jl

julia> apply!(repo, edit, "Rename generated file")
[main 42b6093] Rename generated file
 1 file changed, 0 insertions(+), 0 deletions(-)
 rename generated.jl => generated-renamed.jl (100%)
Applied: 1 file changed, commit 42b6093

```

```jldoctest editing
julia> edit = DeleteFile("examples/generated-renamed.jl")
Edit deletes examples/generated-renamed.jl

julia> apply!(repo, edit, "Remove generated file")
[main ef88bc4] Remove generated file
 1 file changed, 3 deletions(-)
 delete mode 100644 generated-renamed.jl
Applied: 1 file changed, commit ef88bc4

```

## Combining edits

Use [`Combine`](@ref), or the `*` shorthand, when multiple edits are part of one logical change and should be planned together:

```jldoctest editing
julia> source = Handle("examples/ProjectCode.jl", 10)
# examples/ProjectCode.jl 11 - 13:
function bar(x)
    return foo(x) + SCALE
end

julia> destination = eof_handle("examples/notes.txt")
# examples/notes.txt EOF:

julia> edit = Combine(
           InsertBefore(destination, "\nMoved helper source:\n\n" * string(source)),
           Delete(source),
       )
Edit modifies examples/ProjectCode.jl:
11,13c10
< function bar(x)
<     return foo(x) + SCALE
< end
---
Edit modifies examples/notes.txt:
3c4,9
---
>
> Moved helper source:
>
> function bar(x)
>     return foo(x) + SCALE
> end

julia> apply!(repo, edit, "Move helper source to notes")
[main 85a68c7] Move helper source to notes
 2 files changed, 6 insertions(+), 3 deletions(-)
Applied: 2 files changed, commit 85a68c7

```

Equivalent shorthand:

```jldoctest editing
julia> h = Handle("examples/ProjectCode.jl", 6)
# examples/ProjectCode.jl 7 - 9:
function foo(x)
    return x + 2
end

julia> edit = InsertAfter(h, raw"""
       
       function baz(x)
           return foo(x) - 1
       end
       """) * InsertBefore(eof_handle("examples/notes.txt"), "\nAdded baz to ProjectCode.jl\n")
Edit modifies examples/ProjectCode.jl:
10c11,14
---
> function baz(x)
>     return foo(x) - 1
> end
>
Edit modifies examples/notes.txt:
9c10,11
---
>
> Added baz to ProjectCode.jl

julia> apply!(repo, edit, "Add baz and update notes")
[main 2a27115] Add baz and update notes
 2 files changed, 6 insertions(+)
Applied: 2 files changed, commit 2a27115

```

Combined edits are validated after the full combined result is planned. Intermediate states may therefore be invalid Julia syntax, provided the final result is valid.

Planning and validation are all-or-nothing. Applying a combined edit that touches multiple files is still best-effort at the filesystem level: if a later filesystem operation fails, earlier operations may already have been applied. Use version control so changes can be reviewed and recovered.

## Applying edits without version control

For scratch files, generated files, or other changes that should not create a commit, pass an explicit [`NoVersionControl`](@ref) specification.

This mode is explicit so that the call site states that the edit will not be committed by CodeEdit.jl.

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
