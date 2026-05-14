# A first careful edit

Imagine you're maintaining `TrailBlazer` and the first thing you notice is not a crash. It is a number that feels wrong.

A route with a long climb is estimated too optimistically. The formula is probably in `walk_time`, but you do not need to open a file and count lines. Ask CodeEdit.jl for the block.

```@setup first_edit
using CodeEdit

rm("trailblazer"; recursive=true, force=true)
mkpath("trailblazer/src")
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
    climb = route.ascent_m / 600
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
    return "$(route.name): $(route.distance_km) km, about $hours hours"
end
""")

write("trailblazer/test/runtests.jl", raw"""
using Test

include("../src/TrailBlazer.jl")
using .TrailBlazer

@testset "TrailBlazer" begin
    route = Route("Ridge Loop", 12.0, 300)
    @test walk_time(route) ≈ 2.9
    @test route_summary(route) == "Ridge Loop: 12.0 km, about 2.9 hours"
end
""")

run(`git init trailblazer`)
run(`git -C trailblazer config user.email docs@example.com`)
run(`git -C trailblazer config user.name "CodeEdit Docs"`)
run(`git -C trailblazer add .`)
run(`git -C trailblazer commit -m "Initial TrailBlazer project"`)

sleep(1.1)
```

## Start with a handle

[`Handle`](@ref) creates a handle to the block containing a file location. If the location is inside a function, the handle points to the whole function.

```@repl first_edit
h = Handle("trailblazer/src/routes.jl", 7)
```

A header shows the file and line range, followed by the source block itself.

You can also collect handles and search them. The result is a `Set` of handles, because a search may find several blocks.

```@repl first_edit
repo = VersionControl("trailblazer")
matches = search(repo, "walk_time")
```

Here there is only one definition we want:

```@repl first_edit
h = only(search(repo, "function walk_time"))
```

## Turn the handle into an edit

`string(h)` gives the source code for the block. That makes small programmatic edits pleasant: use normal Julia string tools, then wrap the result in an edit value.

```@repl first_edit
replacement = replace(string(h), "route.ascent_m / 600" => "route.ascent_m / 500");
edit = Replace(h, replacement)
```

That displayed diff is the review step. No file has been changed yet.

## Apply through git

For normal source code, use [`VersionControl`](@ref). With `require_view=true`, CodeEdit.jl refuses to apply an edit unless the exact plan has been displayed.

```@repl first_edit
repo = VersionControl("trailblazer"; require_view=true)
apply!(repo, edit, "Estimate steep climbs more conservatively")
```

The edit was written, staged, and committed.

You can inspect the result from Julia:

```@repl first_edit
println.(readlines("trailblazer/src/routes.jl"));
```

And you can run the project test file like any other Julia code:

```@repl first_edit
include("trailblazer/test/runtests.jl")
```

## What just happened?

The important distinction is that CodeEdit.jl separates describing an edit from applying it.

- `Handle(...)` found the relevant block.
- `Replace(h, replacement)` described the change and displayed the diff.
- `apply!(repo, edit, "...")` replanned the edit, checked the displayed plan, wrote the file, and committed it.

This is the rhythm the rest of the guide builds on.
