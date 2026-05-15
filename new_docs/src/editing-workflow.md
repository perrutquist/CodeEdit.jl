# Editing workflows

Edits are ordinary Julia values. They can be constructed independently, combined, displayed as one plan, and applied as one change.

This section demonstrates multi-block and multi-file edits: insertion, replacement, file creation, file movement, deletion, and combined application.

```@setup editing_workflow
using CodeEdit

rm("trailblazer"; recursive=true, force=true)
mkpath("trailblazer/src")
mkpath("trailblazer/notes")
mkpath("trailblazer/test")

write("trailblazer/src/TrailBlazer.jl", raw"""
module TrailBlazer

include("routes.jl")
include("formatting.jl")

export Route, walk_time, route_summary

end
""")

write("trailblazer/src/routes.jl", raw"""
struct Route
    name::String
    distance_km::Float64
    ascent_m::Int
end

function walk_time(route::Route; pace_kmh=5.0)
    hours = route.distance_km / pace_kmh
    climb = route.ascent_m / 500
    return hours + climb
end

function difficulty(route::Route)
    if route.distance_km > 20 || route.ascent_m > 1000
        return :hard
    elseif route.distance_km > 10 || route.ascent_m > 500
        return :moderate
    else
        return :easy
    end
end
""")

write("trailblazer/src/formatting.jl", raw"""
function route_summary(route::Route)
    hours = round(walk_time(route); digits=1)
    level = difficulty(route)
    return "$(route.name): $(route.distance_km) km, about $hours hours, $level"
end
""")

write("trailblazer/notes/release-notes.txt", raw"""
Release notes

The next release should mention the improved climb estimate.
""")

write("trailblazer/test/runtests.jl", raw"""
using Test

include(joinpath(@__DIR__, "../src/TrailBlazer.jl"))
using .TrailBlazer

@testset "TrailBlazer" begin
    route = Route("Ridge Loop", 12.0, 300)
    @test walk_time(route) ≈ 3.0
    @test route_summary(route) == "Ridge Loop: 12.0 km, about 3.0 hours, moderate"
end
""")

run(`git init trailblazer`)
run(`git -C trailblazer config user.email docs@example.com`)
run(`git -C trailblazer config user.name "CodeEdit Docs"`)
run(`git -C trailblazer add .`)
run(`git -C trailblazer commit -m "Initial TrailBlazer workflow project"`)
```

## Insert code near a stable anchor

Insertion edits are anchored to existing handles. This makes the edit independent of absolute line numbers as long as the anchor block can still be matched.

[`InsertAfter`](@ref) inserts code after a block. [`InsertBefore`](@ref) inserts before a block. Raw string literals are useful for Julia source because `$` and backslashes are not interpolated or escaped.

```@repl editing_workflow
difficulty_handle = only(search(handles("trailblazer/src/routes.jl"), "function difficulty"))
packing_edit = InsertAfter(difficulty_handle, raw"""

function packing_note(route::Route)
    if difficulty(route) == :hard
        return "Bring layers, lunch, and a headlamp."
    else
        return "Bring water and a snack."
    end
end
""")
```

## Replace an existing block

Use [`Replace`](@ref) when the whole referenced block should be rewritten.

```@repl editing_workflow
summary_handle = only(search(handles("trailblazer/src/formatting.jl"), "function route_summary"))
new_summary = raw"""
function route_summary(route::Route)
    hours = round(walk_time(route); digits=1)
    level = difficulty(route)
    note = packing_note(route)
    return "$(route.name): $(route.distance_km) km, about $hours hours, $level. $note"
end
""";
summary_edit = Replace(summary_handle, new_summary)
```

## Update exports

`packing_note` should be public too. This is another replacement, this time of the export line.

```@repl editing_workflow
export_handle = only(search(handles("trailblazer/src/TrailBlazer.jl"), "export Route"))
export_edit = Replace(export_handle, "export Route, walk_time, route_summary, packing_note\n")
```

## Add a note at the end of a text file

[`eof_handle`](@ref) points to the end of a file. Use it with `InsertBefore` to append content.

```@repl editing_workflow
notes_edit = InsertBefore(eof_handle("trailblazer/notes/release-notes.txt"), raw"""

Packing suggestions are now included in route summaries.
""")
```

## Combine related edits

[`Combine`](@ref) plans child edits together. The `*` operator is shorthand for combining edits in left-to-right order.

```@repl editing_workflow
edit = packing_edit * summary_edit * export_edit * notes_edit
```

Combined edits are validated against the complete planned result. Intermediate states may be invalid as long as the final file contents are valid.

Apply the combined edit as one commit:

```@repl editing_workflow
repo = VersionControl("trailblazer"; require_view=true)
apply!(repo, edit, "Add packing suggestions to route summaries")
```

The source and notes now tell the same story:

```@repl editing_workflow
println.(readlines("trailblazer/src/routes.jl"));
println.(readlines("trailblazer/src/formatting.jl"));
println.(readlines("trailblazer/src/TrailBlazer.jl"));
println.(readlines("trailblazer/notes/release-notes.txt"));
```

## Create, move, and delete files

File operations are edit values too, so they can be displayed, combined, and applied through the same API as block edits.

[`CreateFile`](@ref) creates a new file:

```@repl editing_workflow
create_edit = CreateFile("trailblazer/notes/checklist.txt", raw"""
Before publishing:

- run tests
- skim route summaries
- check release notes
"""; parse_as=:text)
create_edit
apply!(repo, create_edit, "Add release checklist")
```

[`MoveFile`](@ref) renames or moves a file:

```@repl editing_workflow
move_edit = MoveFile("trailblazer/notes/checklist.txt", "trailblazer/notes/release-checklist.txt")
move_edit
apply!(repo, move_edit, "Rename release checklist")
```

[`DeleteFile`](@ref) deletes a file:

```@repl editing_workflow
delete_edit = DeleteFile("trailblazer/notes/release-checklist.txt")
delete_edit
apply!(repo, delete_edit, "Remove temporary release checklist")
```

Move and delete operations reject source or destination paths that are symlinks.

## Delete a block

The [`Delete`](@ref) edit removes the block referenced by a handle. EOF handles are unaffected.

Here you decide the release note has done its job and remove the paragraph you just added.

```@repl editing_workflow
note_handle = only(search(handles("trailblazer/notes/release-notes.txt"), "Packing suggestions"))
delete_note = Delete(note_handle)
delete_note
apply!(repo, delete_note, "Remove temporary packing note")
```

## Moving code between files

Moving a block can be expressed as a combined insertion and deletion. Insert the old source at the destination first, then delete the original handle.

```@repl editing_workflow
source = only(search(handles("trailblazer/src/routes.jl"), "function packing_note"))
destination = eof_handle("trailblazer/src/formatting.jl")
move_packing = InsertBefore(destination, "\n" * string(source)) * Delete(source)
move_packing
apply!(repo, move_packing, "Move packing note to formatting helpers")
```

Planning and validation for a combined edit are all-or-nothing. The filesystem writes themselves are not transactional, so git-backed editing is recommended for important changes.

## Existing handles after edits

After an edit is applied, CodeEdit updates existing handles when their blocks can still be matched. Handles whose blocks were deleted become invalid.

```@repl editing_workflow
is_valid(source)
is_valid(destination)
```

If files are changed outside CodeEdit.jl, cached handles are automatically reindexed when file timestamps change. You can call [`reindex`](@ref) explicitly when you want to update all cached handles right away.
