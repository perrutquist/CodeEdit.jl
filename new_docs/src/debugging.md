# Debugging

Stacktraces contain source locations. CodeEdit can search handles for blocks whose locations occur in a captured trace, which makes it possible to move from an error to the corresponding source block.

```@setup debugging
using CodeEdit

rm("trailblazer"; recursive=true, force=true)
mkpath("trailblazer/src")
mkpath("trailblazer/test")

write("trailblazer/src/TrailBlazer.jl", raw"""
module TrailBlazer

include("routes.jl")
include("formatting.jl")

export Route, walk_time, average_speed, route_summary

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

function average_speed(route::Route)
    return route.distance_km / walk_time(route)
end
""")

write("trailblazer/src/formatting.jl", raw"""
function route_summary(route::Route)
    hours = round(walk_time(route); digits=1)
    speed = round(average_speed(route); digits=1)
    return "$(route.name): $(route.distance_km) km, about $hours hours at $speed km/h"
end
""")

write("trailblazer/test/runtests.jl", raw"""
using Test

include(joinpath(@__DIR__, "../src/TrailBlazer.jl"))
using .TrailBlazer

@testset "TrailBlazer" begin
    route = Route("Ridge Loop", 12.0, 300)
    @test walk_time(route) ≈ 3.0
    @test average_speed(route) ≈ 4.0
end
""")

run(`git init trailblazer`)
run(`git -C trailblazer config user.email docs@example.com`)
run(`git -C trailblazer config user.name "CodeEdit Docs"`)
run(`git -C trailblazer add .`)
run(`git -C trailblazer commit -m "Initial debugging project"`)

include("trailblazer/src/TrailBlazer.jl")
using .TrailBlazer

trace = try
    route_summary(Route("Nowhere", 0.0, 0))
catch
    catch_backtrace()
end

sleep(1.1)
```

## Capture the trace

At the REPL, capture the backtrace when handling an exception:

```julia
trace = try
    route_summary(Route("Nowhere", 0.0, 0))
catch
    catch_backtrace()
end
```

The setup for this page has already captured such a trace. Search project handles for source locations that occur in it:

```@repl debugging
hs = handles("trailblazer/src", "*.jl")
matches = search(hs, trace)
```

The result contains blocks whose source locations appear in the stacktrace.

If an error was just caught at the Julia REPL, the caught `ExceptionStack` is available as `err` and can be searched in the same way:

```julia
matches = search(hs, err)
```

## Inspect the relevant block

When several blocks occur in the trace, refine the result with a text search:

```@repl debugging
search(matches, "average_speed")
```

The selected block divides distance by walking time. For a zero-length route, reject non-positive walking times explicitly.

## Replace the function

```@repl debugging
h = only(search(matches, "function average_speed"))
fixed = raw"""
function average_speed(route::Route)
    hours = walk_time(route)
    if hours <= 0
        throw(ArgumentError("route must take a positive amount of time"))
    end
    return route.distance_km / hours
end
""";
edit = Replace(h, fixed)
```

Apply the fix through git:

```@repl debugging
repo = VersionControl("trailblazer"; require_view=true)
apply!(repo, edit, "Reject routes with non-positive walking time")
```

The source now says exactly what the new behavior is:

```@repl debugging
println.(readlines("trailblazer/src/routes.jl"));
```

## Add a regression test

Insert a test after the existing average speed assertion.

```@repl debugging
test_handle = Handle("trailblazer/test/runtests.jl", 8)
new_tests = replace(
    string(test_handle),
    "@test average_speed(route) ≈ 4.0" => "@test average_speed(route) ≈ 4.0\n    @test_throws ArgumentError average_speed(Route(\"Nowhere\", 0.0, 0))",
);
test_edit = Replace(test_handle, new_tests)
```

```@repl debugging
apply!(repo, test_edit, "Test zero-distance route error")
include("trailblazer/test/runtests.jl")
```

## Searching included files

For a package entry point that uses `include`, you can start with the entry point and follow includes recursively:

```@repl debugging
all_project_handles = handles("trailblazer/src/TrailBlazer.jl"; includes=true)
search(all_project_handles, "average_speed")
```

This is often the most convenient way to search a package: begin at the same entry point Julia loads.
