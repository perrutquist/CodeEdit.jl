# Safety

CodeEdit is conservative by design. It separates edit construction from filesystem mutation, and it encourages applying source changes through an explicit version-control policy.

!!! note
    Constructing an edit does not modify files. Only [`apply!`](@ref) writes changes to disk.

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

When a git-backed repository specification is created with `require_view=true`, an edit must be displayed, printed, or converted to a string before it can be applied.

```@repl safety
repo = VersionControl("trailblazer"; require_view=true)
h = only(search(handles("trailblazer/src/routes.jl"), "function walk_time"))
replacement = replace(string(h), "route.ascent_m / 500" => "route.ascent_m / 550");
edit = Replace(h, replacement)
```

The displayed diff is remembered. When [`apply!`](@ref) runs, CodeEdit replans the edit and rejects it if the current plan differs from the displayed one. This prevents a stale reviewed plan from being applied after the file has changed.

```@repl safety
apply!(repo, edit, "Tune climb estimate")
```

Calling `display(edit)` or `string(edit)` also marks an edit as displayed. Use [`displayed!`](@ref) only when an edit should be marked explicitly.

## Git-backed editing

[`VersionControl`](@ref) and [`GitVersionControl`](@ref) describe a git repository together with default options for [`apply!`](@ref).

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

The displayed result is brief; the returned object contains details such as changed paths, commits, and diff text.

```@repl safety
h = only(search(handles("trailblazer/src/routes.jl"), "function walk_time"))
edit = Replace(h, replace(string(h), "route.ascent_m / 550" => "route.ascent_m / 500"))
apply!(repo, edit, "Restore climb estimate")
```

You can provide the commit message at apply time, or store a default message in the version-control object and call `apply!` without a positional message.

## Dirty files and precommits

By default, CodeEdit can reject edits when relevant tracked files are dirty. This keeps the reviewed diff focused on the edit being applied.

If dirty tracked work is intentional, pass a `precommit_message`. CodeEdit will commit the existing dirty tracked files before formatting or applying the requested edit.

Common options can be stored in `VersionControl(path; kwargs...)` or passed to `apply!`:

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

Julia files are reparsed before edits are applied. If the final result would introduce a syntax error, the edit is rejected.

Combined edits are planned and validated as a unit. Intermediate states may be invalid Julia syntax as long as the final result is valid.

## Applying without version control

Most source edits should go through git. For scratch files, generated output, or temporary notes, use [`NoVersionControl`](@ref) explicitly.

```@repl safety
write("trailblazer/tmp/session-note.txt", "status = old\n")
scratch = Handle("trailblazer/tmp/session-note.txt", 1; parse_as=:text)
scratch_edit = Replace(scratch, "status = new\n")
apply!(NoVersionControl(require_view=true), scratch_edit)
println.(readlines("trailblazer/tmp/session-note.txt"));
```

The explicit `NoVersionControl(...)` at the call site is intentional. It makes the absence of a git commit visible in code review and in REPL history.

Calling `apply!(edit)` without either `VersionControl` or `NoVersionControl` always errors.

## Limitations

CodeEdit provides planning and validation, but it is not a transactional filesystem.

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

Revise.jl is an optional weak dependency. When Revise is loaded, CodeEdit calls `Revise.revise()` after a successful edit. Revise failures are reported as warnings because the filesystem edit has already happened.

That means a REPL-driven workflow can often look like this:

1. inspect a function;
2. edit it through CodeEdit.jl;
3. apply and commit;
4. keep experimenting without restarting Julia.
