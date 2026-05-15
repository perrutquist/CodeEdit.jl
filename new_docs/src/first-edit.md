# A first edit

This section demonstrates the smallest complete workflow: locate a function, construct a replacement, review the resulting diff, and apply it through git.

The example project estimates walking time for hiking routes. The climb component is too optimistic, and the formula is in `walk_time`.

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

include(joinpath(@__DIR__, "../src/TrailBlazer.jl"))
using .TrailBlazer

@testset "TrailBlazer" begin
    route = Route("Ridge Loop", 12.0, 300)
    @test walk_time(route) ≈ 3.0
    @test route_summary(route) == "Ridge Loop: 12.0 km, about 3.0 hours"
end
""")

run(`git init trailblazer`)
run(`git -C trailblazer config user.email docs@example.com`)
run(`git -C trailblazer config user.name "CodeEdit Docs"`)
run(`git -C trailblazer add .`)
run(`git -C trailblazer commit -m "Initial TrailBlazer project"`)
```

## Search for a handle

Search returns handles for blocks whose contents or source locations match the query. A search may find more than one block, so the result is a set.

```@repl first_edit
repo = VersionControl("trailblazer")
matches = search(repo, "walk_time")
```

[`Handle`](@ref) can also be constructed from a file and line number. If the location lies inside a function, the handle refers to the whole function block.

```@repl first_edit
h = Handle("trailblazer/src/routes.jl", 7)
```

Displayed handles show the file, line range, and source block.

For this example, select the single matching definition directly:

```@repl first_edit
h = only(search(repo, "function walk_time"))
```

## Construct an edit

`string(h)` returns the source text for the block. Ordinary Julia string operations can be used to build the replacement text before wrapping it in an edit value.

```@repl first_edit
replacement = replace(string(h), "route.ascent_m / 600" => "route.ascent_m / 500");
edit = Replace(h, replacement)
```

The displayed diff is the review step. No file is changed until [`apply!`](@ref) is called.

## Apply through git

For source files, use [`VersionControl`](@ref). With `require_view=true`, CodeEdit refuses to apply an edit unless the exact plan has been displayed.

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
include("trailblazer/test/runtests.jl");
```

## Summary

CodeEdit separates edit construction from edit application.

- `Handle(...)` identified the source block.
- `Replace(h, replacement)` described the change and displayed the diff.
- `apply!(repo, edit, "...")` replanned the edit, verified the displayed plan, wrote the file, and committed it.

The same pattern applies to larger edits.
