# Changing more than one thing

A feature request arrives: route summaries should include a packing suggestion, and the release notes should mention it.

This is small, but it touches more than one place. CodeEdit.jl is comfortable with that. You can build separate edits, review their combined plan, and apply them as one commit.

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

include("../src/TrailBlazer.jl")
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

sleep(1.1)
```

## Insert code near a stable anchor

A new helper belongs near `difficulty`, because both functions classify a route.

[`InsertAfter`](@ref) inserts code after a block. [`InsertBefore`](@ref) inserts before a block. Use raw string literals for Julia code so `$` and backslashes are not accidentally escaped.

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

Now include the new note in `route_summary`.

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

[`Combine`](@ref) plans child edits together. The `*` operator is shorthand for combining edits left-to-right.

```@repl editing_workflow
edit = packing_edit * summary_edit * export_edit * notes_edit
```

Combined edits are validated after the complete planned result, so intermediate states can be temporarily invalid as long as the final files are valid.

Apply the whole feature as one commit:

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

## Create, move, and delete whole files

CodeEdit.jl can also describe file-level changes.

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

Source or destination symlink paths are rejected for move and delete file operations.

## Delete a block

The [`Delete`](@ref) edit removes the block referenced by a handle. EOF handles are unaffected.

Here Lena decides the release note has done its job and removes the paragraph she just added.

```@repl editing_workflow
note_handle = only(search(handles("trailblazer/notes/release-notes.txt"), "Packing suggestions"))
delete_note = Delete(note_handle)
delete_note
apply!(repo, delete_note, "Remove temporary packing note")
```

## Moving code between files

Moving a block is just a combined insert and delete. The order matters: insert the old source at the destination, then delete the original handle.

```@repl editing_workflow
source = only(search(handles("trailblazer/src/routes.jl"), "function packing_note"))
destination = eof_handle("trailblazer/src/formatting.jl")
move_packing = InsertBefore(destination, "\n" * string(source)) * Delete(source)
move_packing
apply!(repo, move_packing, "Move packing note to formatting helpers")
```

If a combined edit touches several files, planning and validation are all-or-nothing. The filesystem apply is still best-effort, so use git-backed editing for important work.

## Existing handles adapt

After edits, CodeEdit.jl updates handles when it can still match their blocks. Deleted blocks become invalid.

```@repl editing_workflow
is_valid(source)
is_valid(destination)
```

If files are changed outside CodeEdit.jl, cached handles are automatically reindexed when file timestamps change. You can call [`reindex`](@ref) explicitly when you want to update all cached handles right away.
