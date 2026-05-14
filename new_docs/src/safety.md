# Working safely

CodeEdit.jl is intentionally conservative. It is not trying to be a clever text editor. It is trying to make small source changes reviewable, reproducible, and easy to recover from.

The central rule is simple:

> Building an edit does not modify files. Applying an edit does.

```@setup safety
using CodeEdit

rm("trailblazer"; recursive=true, force=true)
mkpath("trailblazer/src")
mkpath("trailblazer/tmp")

write("trailblazer/src/TrailBlazer.jl", raw"""
module TrailBlazer

include("routes.jl")

export Route, walk_time

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
""")

run(`git init trailblazer`)
run(`git -C trailblazer config user.email docs@example.com`)
run(`git -C trailblazer config user.name "CodeEdit Docs"`)
run(`git -C trailblazer add .`)
run(`git -C trailblazer commit -m "Initial safety project"`)

sleep(1.1)
```

## Require review before apply

When you create a git-backed repository specification with `require_view=true`, an edit must be displayed, printed, or converted to a string before it can be applied.

```@repl safety
repo = VersionControl("trailblazer"; require_view=true)
h = only(search(handles("trailblazer/src/routes.jl"), "function walk_time"))
replacement = replace(string(h), "route.ascent_m / 500" => "route.ascent_m / 550");
edit = Replace(h, replacement)
```

The displayed diff is remembered. When [`apply!`](@ref) runs, CodeEdit.jl replans the edit and rejects it if the current plan differs from the displayed one. This protects you from applying a stale edit after the file changed.

```@repl safety
apply!(repo, edit, "Tune climb estimate")
```

Calling `display(edit)` or `string(edit)` also marks an edit as displayed.

If you need to mark an edit as displayed explicitly, use [`displayed!`](@ref).

## Git-backed editing

[`VersionControl`](@ref) and [`GitVersionControl`](@ref) describe a git repository and default apply options.

```@repl safety
VersionControl("trailblazer"; require_view=true)
GitVersionControl("trailblazer"; require_view=true)
```

A normal git-backed apply:

1. plans the edit;
2. validates the final file contents;
3. writes the files;
4. stages affected paths;
5. creates a commit;
6. returns an `ApplyResult`.

The displayed result is brief, but the object contains details such as changed paths, commits, and diff text.

```@repl safety
h = only(search(handles("trailblazer/src/routes.jl"), "function walk_time"))
edit = Replace(h, replace(string(h), "route.ascent_m / 550" => "route.ascent_m / 500"))
apply!(repo, edit, "Restore climb estimate")
```

You can provide the commit message at apply time, or store a default message in the version-control object and call `apply!` without a positional message.

## Dirty files and precommits

By default, CodeEdit.jl can reject edits when relevant tracked files are dirty. This keeps the reviewed diff focused on the edit you are applying.

For workflows where you intentionally have dirty tracked work, pass a `precommit_message`. CodeEdit.jl will commit the existing dirty tracked files before formatting or applying the requested edit.

Important options can be stored in `VersionControl(path; kwargs...)` or passed to `apply!`:

- `require_view`: require the edit plan to have been displayed;
- `require_versioning`: reject edits to existing untracked files and reject creation outside the worktree;
- `require_clean`: reject dirty tracked files in scope;
- `atomic_repo`: check/precommit the whole repository rather than only affected files;
- `precommit_message`: commit existing dirty tracked work before the edit;
- `formatter`: format affected files before the edit;
- `preformat`: choose whether to run the formatter before applying;
- `format_message`: commit message for formatter-only changes;
- `default_message`: commit message used when none is passed to `apply!`.

## Validation

Julia files are reparsed before edits are applied. If the final result would introduce syntax errors, the edit is rejected.

Combined edits are planned and validated as a unit, so intermediate states can be temporarily invalid as long as the final result is valid.

## Applying without version control

Most source edits should go through git. But sometimes you are changing a scratch file, generated output, or a temporary note.

For those cases, use [`NoVersionControl`](@ref) explicitly.

```@repl safety
write("trailblazer/tmp/session-note.txt", "status = old\n")
scratch = Handle("trailblazer/tmp/session-note.txt", 1; parse_as=:text)
scratch_edit = Replace(scratch, "status = new\n")
apply!(NoVersionControl(require_view=true), scratch_edit)
println.(readlines("trailblazer/tmp/session-note.txt"));
```

The explicit `NoVersionControl(...)` at the call site is intentional. It makes the lack of a git commit visible in code review and in your own REPL history.

Calling `apply!(edit)` without either `VersionControl` or `NoVersionControl` always errors.

## What is not guaranteed

CodeEdit.jl gives you careful planning and validation, but it is not a transactional filesystem.

In particular:

- multi-file applies are not atomic at the filesystem level;
- there is no built-in undo stack;
- handles can become invalid when their referenced blocks are deleted or cannot be matched;
- no-version-control edits are not committed unless you commit them yourself.

The safest everyday pattern is:

1. work in a git repository;
2. keep edits small;
3. require review for edits that matter;
4. apply through `VersionControl`;
5. let git be your undo and audit trail.

## Revise integration

Revise.jl is an optional weak dependency. When Revise is loaded, CodeEdit.jl calls `Revise.revise()` after a successful edit. Revise failures are reported as warnings because the filesystem edit has already happened.

That means a REPL-driven workflow can often look like this:

1. inspect a function;
2. edit it through CodeEdit.jl;
3. apply and commit;
4. keep experimenting without restarting Julia.
