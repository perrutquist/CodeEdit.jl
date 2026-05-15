# CodeEdit.jl

CodeEdit provides a small API for locating source blocks, constructing edits, reviewing planned changes, and applying them to a working tree. It is intended for REPL-driven maintenance of Julia projects, where changes should be explicit and recoverable.

The main objects are handles and edits. A [`Handle`](@ref) identifies a block of source code or text. Edit values such as [`Replace`](@ref), [`InsertBefore`](@ref), [`InsertAfter`](@ref), and [`Delete`](@ref) describe changes to those blocks. Applying an edit writes the result to disk; applying through [`VersionControl`](@ref) also stages and commits the affected files.

## Basic workflow

The usual workflow is:

```text
find a handle -> construct an edit -> review the plan -> apply -> commit
```

Most examples use git-backed editing, which is the recommended workflow for source files.

```@setup index
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
    @test walk_time(route) ≈ 2.9
    @test route_summary(route) == "Ridge Loop: 12.0 km, about 2.9 hours"
end
""")

run(`git init trailblazer`)
run(`git -C trailblazer config user.email docs@example.com`)
run(`git -C trailblazer config user.name "CodeEdit Docs"`)
run(`git -C trailblazer add .`)
run(`git -C trailblazer commit -m "Initial TrailBlazer project"`)
```

The setup above creates a small project used by the examples:

```@repl index
println.(readlines("trailblazer/src/TrailBlazer.jl"));
println.(readlines("trailblazer/src/routes.jl"));
println.(readlines("trailblazer/src/formatting.jl"));
```

Create a repository specification before applying source edits. The `require_view=true` option requires an edit plan to be displayed before it can be applied, and the displayed plan must still match the current files.

```@repl index
repo = VersionControl("trailblazer"; require_view=true)
```

This value records the version-control policy used by later calls to [`apply!`](@ref).

## A complete edit

Suppose the climb component of `walk_time` needs to be adjusted. Search the repository and select the matching source block:

```@repl index
pwd()
h = only(search(repo, "function walk_time"))
```

The returned handle displays its file, line range, and source block.

Construct an edit from the handle. This records the requested change, but does not modify the filesystem. Displaying the edit shows the planned diff and records the reviewed plan.

```@repl index
updated = replace(string(h), "route.ascent_m / 600" => "route.ascent_m / 500");
edit = Replace(h, updated)
```

Apply it through git:

```@repl index
apply!(repo, edit, "Account for steeper climbs in walk time")
```

And the file on disk now says what the commit says it says:

```@repl index
println.(readlines("trailblazer/src/routes.jl"));
```

## Manual outline

The remaining manual pages introduce the API by task:

- [A first edit](first-edit.md) shows one reviewed replacement applied through git.
- [Finding code](finding-code.md) describes handles, search, includes, methods, and docstrings.
- [Editing workflows](editing-workflow.md) covers insertion, deletion, file operations, and combined edits.
- [Debugging](debugging.md) shows how to move from a stacktrace to the source block that should be changed.
- [Safety](safety.md) documents review requirements, git integration, no-version-control mode, and failure modes.
- [API reference](reference.md) lists the exported names.

The common pattern is to find the relevant block, construct an edit, review the plan, and apply it under an explicit version-control policy.
