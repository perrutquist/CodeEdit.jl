# Finding code

CodeEdit represents source locations as handles. Handles can be collected from files, directories, include graphs, methods, stacktraces, and search results.

This section covers the main ways to move from a name or location to the block of source that should be inspected or edited.

```@setup finding_code
using CodeEdit

rm("trailblazer"; recursive=true, force=true)
mkpath("trailblazer/src")
mkpath("trailblazer/notes")

write("trailblazer/src/TrailBlazer.jl", raw"""
module TrailBlazer

include("routes.jl")
include("formatting.jl")
include("packing.jl")

export Route, walk_time, route_summary, packing_note

end
""")

write("trailblazer/src/routes.jl", raw"""
"One route that can be walked in a day."
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

write("trailblazer/src/packing.jl", raw"""
function packing_note(route::Route)
    if difficulty(route) == :hard
        return "Bring layers, lunch, and a headlamp."
    else
        return "Bring water and a snack."
    end
end
""")

write("trailblazer/notes/release-notes.txt", raw"""
Release notes

The next release should mention the improved climb estimate.

Remember to document packing suggestions.
""")

run(`git init trailblazer`)
run(`git -C trailblazer config user.email docs@example.com`)
run(`git -C trailblazer config user.name "CodeEdit Docs"`)
run(`git -C trailblazer add .`)
run(`git -C trailblazer commit -m "Initial searchable TrailBlazer project"`)
```

## Listing blocks in a file

[`handles`](@ref) returns the blocks CodeEdit sees in a file. Julia files are split into top-level forms such as functions, structs, constants, includes, imports, exports, and module boundaries. A special EOF handle is included for insertions at the end of the file.

```@repl finding_code
hs = handles("trailblazer/src/routes.jl")
```

A set of handles is displayed as an overview. Display one handle to see the full block:

```@repl finding_code
first(search(hs, "function difficulty"))
```

For non-Julia files, CodeEdit works with text blocks. By default, non-`.jl` files are parsed as text paragraphs.

```@repl finding_code
handles("trailblazer/notes/release-notes.txt")
```

You can override parsing with `parse_as=:julia` or `parse_as=:text` when needed.

## Searching source

The simplest search is a text query over a collection of handles:

```@repl finding_code
search(handles("trailblazer/src", "*.jl"), "difficulty")
```

Search accepts strings and regular expressions:

```@repl finding_code
search(handles("trailblazer/src", "*.jl"), r"packing|headlamp")
```

The search functions also accept paths directly, so this is equivalent:

```@repl finding_code
search("trailblazer/src/packing.jl", "headlamp")
```

A directory plus glob searches matching files:

```@repl finding_code
search("trailblazer/src", "*.jl", "route_summary")
```

## Following includes

When a file contains `include` statements, pass `includes=true` to follow them recursively from the starting file.

```@repl finding_code
hs = handles("trailblazer/src/TrailBlazer.jl"; includes=true)
search(hs, "packing_note")
```

Recursive include traversal uses cycle detection, so include loops are visited at most once.

## Inspecting a handle

A handle records the file, line range, parse mode, and source text for a block:

```@repl finding_code
h = only(search(hs, "struct Route"))
filepath(h)
lines(h)
docstring(h)
is_valid(h)
```

The docstring belongs to the block, so a documented type or function can be moved and edited as a unit.

You can also check whether a handle came from Julia source or plain text:

```@repl finding_code
is_julia(h)
is_text(h)
```

## From a loaded method to source

Sometimes the code is already loaded and you know the function object, not the file. `Handle(method)` returns the source block for a method when source information is available.

```@repl finding_code
include("trailblazer/src/TrailBlazer.jl")
using .TrailBlazer
Handle(first(methods(walk_time)))
```

This is useful when the relevant object is already loaded in the current Julia session.

## Matching paths and versioned files

Search results can be filtered by path or by version-control status. [`filepath_matches`](@ref) builds a predicate from a regular expression:

```@repl finding_code
all_handles = handles("trailblazer/src", "*.jl")
filter(filepath_matches(r"formatting"), all_handles)
```

If you are editing through git, you can ask which handles belong to tracked files:

```@repl finding_code
repo = VersionControl("trailblazer")
filter(is_versioned(repo), all_handles)
```

These predicates are ordinary Julia functions and can be combined with `filter`, comprehensions, or other collection operations.
