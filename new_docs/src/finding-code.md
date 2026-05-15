# Finding your way around

Real projects rarely fail in the file you already have open.

This page follows the kind of questions you run into while maintaining a project:

- "Where is this behavior implemented?"
- "What else is related to this name?"
- "Can I get from a loaded method back to its source?"

CodeEdit.jl answers those questions with handles.

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

[`handles`](@ref) returns handles for the blocks CodeEdit.jl sees in a file. Julia files are split into top-level source blocks: functions, structs, constants, includes, imports, exports, module boundary lines, and similar forms. A special EOF handle is also included.

```@repl finding_code
hs = handles("trailblazer/src/routes.jl")
```

A set of handles is displayed as an overview. Display one handle to see the full block:

```@repl finding_code
first(search(hs, "function difficulty"))
```

For non-Julia files, CodeEdit.jl can work with text blocks too. By default, non-`.jl` files are parsed as text paragraphs.

```@repl finding_code
handles("trailblazer/notes/release-notes.txt")
```

You can override parsing with `parse_as=:julia` or `parse_as=:text` when needed.

## Searching source

The simplest search is text search over handles:

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

The package entry point contains `include` statements. If you start from that file, `includes=true` follows them recursively.

```@repl finding_code
hs = handles("trailblazer/src/TrailBlazer.jl"; includes=true)
search(hs, "packing_note")
```

Recursive include traversal uses cycle detection, so include loops are visited at most once.

## Asking about a handle

A handle carries useful facts about its block:

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

That is a natural REPL move: inspect behavior, find the method, turn it into editable source.

## Matching paths and versioned files

When a search gets noisy, filter the handles. `filepath_matches` is useful with regular expressions:

```@repl finding_code
all_handles = handles("trailblazer/src", "*.jl")
filter(filepath_matches(r"formatting"), all_handles)
```

If you are editing through git, you can ask which handles belong to tracked files:

```@repl finding_code
repo = VersionControl("trailblazer")
filter(is_versioned(repo), all_handles)
```

Together, these small tools let you navigate source in terms of blocks, methods, files, and names rather than raw line numbers.
