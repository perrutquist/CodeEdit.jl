# CodeEdit.jl

CodeEdit.jl is a Julia package for making small, deliberate source edits from the REPL.

The easiest way to understand it is to follow a working day.

You are maintaining a small package called `TrailBlazer`. It plans weekend hikes, estimates walking time, and formats little route summaries. A bug report arrives. Then a feature request. Then a failing stacktrace. You could jump between editor tabs, copy line numbers by hand, and hope your worktree still looks the same when you save.

Or you can let CodeEdit.jl turn source locations into handles, handles into reviewed edits, and reviewed edits into git commits.

## The shape of the workflow

CodeEdit.jl keeps editing explicit:

```text
Handle -> Edit -> Displayed plan -> Apply -> Commit
```

A [`Handle`](@ref) points to one block of source code or text. An edit such as [`Replace`](@ref), [`InsertBefore`](@ref), [`InsertAfter`](@ref), or [`Delete`](@ref) describes a change without touching the filesystem. Displaying the edit shows the exact plan. Applying through [`VersionControl`](@ref) writes the files, stages them, and commits the result.

Most examples in this guide use git-backed editing, because that is the intended everyday workflow.

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

Here is the tiny package we will work on:

```@repl index
println.(readlines("trailblazer/src/TrailBlazer.jl"));
println.(readlines("trailblazer/src/routes.jl"));
println.(readlines("trailblazer/src/formatting.jl"));
```

Now create a repository specification. The `require_view=true` option means an edit must be displayed before it can be applied, and the plan shown to you must still be current when you apply it.

```@repl index
repo = VersionControl("trailblazer"; require_view=true)
```

That one value is the boundary between "I am thinking about a change" and "write this change and commit it".

## A tiny edit, end to end

A bug report says walking time is too optimistic for steep routes. The `walk_time` function lives somewhere in the project. We can search the tracked source files and ask for the matching block:

```@repl index
h = only(search(handles("trailblazer/src", "*.jl"), "function walk_time"))
```

Because the line above does not end in a semicolon, Documenter shows the handle. At the REPL, this is one of the nicest parts of CodeEdit.jl: locating code also displays the block you are about to change.

Now build an edit. Constructing the edit still does not touch the file. Leaving off the semicolon displays the diff and records that this is the plan you reviewed.

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

## Where to go next

Read the guide as a story:

- [A first careful edit](first-edit.md) starts with a bug report and follows one reviewed change to a commit.
- [Finding your way around](finding-code.md) shows how handles, search, includes, methods, and docstrings help you orient yourself.
- [Changing more than one thing](editing-workflow.md) covers inserting, deleting, creating, moving, and combining edits.
- [Following an error home](debugging.md) starts from a stacktrace and lands on the function that needs fixing.
- [Working safely](safety.md) explains the review checks, git integration, no-version-control mode, and failure modes.
- [API reference](reference.md) gathers the public API in one place.

The rest of the manual uses small examples, but the goal is the same as real work: find the code, understand it, change it, review the plan, and leave a useful commit behind.
