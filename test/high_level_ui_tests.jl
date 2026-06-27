function write_demo_workspace(root)
    examples = mkpath(joinpath(root, "examples"))
    write(joinpath(examples, "helpers.jl"), "helper(x) = x + 1\n")
    write(joinpath(examples, "notes.txt"), "First note.\n\nSecond note.\n")
    write(
        joinpath(examples, "DemoPackage.jl"),
        """
        module DemoPackage

        include("helpers.jl")

        const DEFAULT_LIMIT = 10

        function foo(x)
            y = helper(x)
            z = y * 2
            return z
        end

        function increment(x)
            return x + 1
        end

        "Return the documented value."
        function documented(x)
            return x
        end

        function old_function_name()
            return foo(1)
        end

        function obsolete()
            return :remove_me
        end

        end
        """,
    )
    write(
        joinpath(examples, "error-example.jl"),
        """
        function inner(x)
            error("bad input: \$x")
        end

        function outer(x)
            return inner(x + 1)
        end
        """,
    )
    return examples
end

function show_plain(x)
    return sprint(show, MIME"text/plain"(), x)
end

@testset "workspace constructors, block lookup, metadata, and display vocabulary" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            write_demo_workspace(dir)

            ws = workspace("examples")
            @test ws isa Workspace
            @test repo("examples") isa Workspace
            @test project("examples") isa Workspace
            @test codebase("examples") isa Workspace

            ws_shown = show_plain(ws)
            @test occursin("Workspace", ws_shown)
            @test occursin("git=", ws_shown)
            @test occursin("review=", ws_shown)

            bs = blocks(ws)
            @test !isempty(bs)
            blocks_shown = show_plain(bs)
            @test occursin("block", lowercase(blocks_shown))
            @test !occursin("handle", lowercase(blocks_shown))

            b = block("examples/DemoPackage.jl:14")
            @test b isa Block
            @test ws["DemoPackage.jl:14"] == b
            @test block("examples/DemoPackage.jl:13") == b
            @test String(b) == source(b)
            @test text(b) == source(b)
            @test occursin("function increment", source(b))
            @test endswith(path(b), "examples/DemoPackage.jl")
            @test lines(b) == 13:15
            @test last(span(b)) == 13:15

            block_shown = show_plain(b)
            @test occursin("#", block_shown)
            @test occursin("13 - 15", block_shown)
            @test occursin("function increment", block_shown)
            @test !occursin("Block", block_shown)

            documented = only(find(ws, "function documented"))
            @test docstring(documented) == "Return the documented value."
            @test docs(documented) == docstring(documented)

            @test_throws ArgumentError block("examples/DemoPackage.jl")
        end
    end
end

@testset "listing blocks, includes, text parsing, and selector aliases" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            write_demo_workspace(dir)

            no_includes = blocks("examples/DemoPackage.jl")
            with_includes = blocks("examples/DemoPackage.jl"; follow_includes=true)
            with_legacy_include_name = blocks("examples/DemoPackage.jl"; includes=true)

            @test isempty(find(no_includes, "helper(x) = x + 1"))
            @test length(find(with_includes, "helper(x) = x + 1")) == 1
            @test length(find(with_legacy_include_name, "helper(x) = x + 1")) == 1

            notes = blocks("examples/notes.txt")
            @test length(find(notes, "First note.")) == 1
            @test length(find(notes, "Second note.")) == 1

            text_block = block("examples/notes.txt:1"; as=:text)
            @test source(text_block) == "First note.\n"

            julia_without_extension = joinpath("examples", "script")
            write(julia_without_extension, "script_value = 1\n")
            @test length(find(blocks(julia_without_extension; as=:julia), "script_value")) == 1
        end
    end
end

@testset "find, search, grep, predicates, globs, and block collections" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            write_demo_workspace(dir)
            ws = workspace("examples")

            @test length(find(ws, "DEFAULT_LIMIT")) == 1
            @test find(ws, "DEFAULT_LIMIT") == search(ws, "DEFAULT_LIMIT")
            @test find(ws, "DEFAULT_LIMIT") == grep(ws, "DEFAULT_LIMIT")
            @test length(find(ws, r"function .*increment")) == 1
            @test length(find(ws, "helper"; files="**/*.jl")) == 3
            @test length(find("examples/DemoPackage.jl", "DEFAULT_LIMIT")) == 1
            @test length(find("examples/**/*.jl", "old_function_name")) == 1

            funcs = find(ws, "function")
            old = find(ws, "old_function_name")
            @test length(intersect(funcs, old)) == 1
            @test only(old) == only(find(funcs, "old_function_name"))

            predicate_matches = find(ws) do b
                occursin("function", source(b)) && endswith(path(b), "DemoPackage.jl")
            end
            @test length(predicate_matches) == 5
            @test all(b -> occursin("function", source(b)), predicate_matches)

            sorted = sort(collect(funcs))
            @test !isempty(sorted)

            @test_throws Exception only(find(ws, "function"))
            @test_throws Exception only(find(ws, "does_not_exist"))
        end
    end
end

@testset "replace, insert, delete, patch combining, and non-git apply" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            write_demo_workspace(dir)
            ws = workspace("examples"; git=false, review=true)

            increment = only(find(ws, "function increment"))
            p = replace(increment, "x + 1" => "x + 2")
            @test p isa Patch

            shown = show_plain(p)
            @test occursin("Patch modifies", shown)
            @test !occursin("Edit modifies", shown)
            @test occursin("<", shown)
            @test occursin(">", shown)

            apply!(p; git=false, yes=true)
            @test occursin("x + 2", read("examples/DemoPackage.jl", String))

            increment = only(find(ws, "function increment"))
            whole_block = replace(
                increment,
                """
                function increment(x)
                    return x + 10
                end
                """,
            )
            show_plain(whole_block)
            apply!(whole_block; git=false, yes=true)
            @test occursin("x + 10", read("examples/DemoPackage.jl", String))

            foo = only(find(ws, "function foo"))
            multiple_replacements = replace(
                foo,
                "y = helper(x)" => "y = helper(abs(x))",
                "z = y * 2" => "z = y * DEFAULT_LIMIT",
            )
            show_plain(multiple_replacements)
            apply!(multiple_replacements; git=false, yes=true)

            text_after_foo = read("examples/DemoPackage.jl", String)
            @test occursin("y = helper(abs(x))", text_after_foo)
            @test occursin("z = y * DEFAULT_LIMIT", text_after_foo)

            obsolete = only(find(ws, "function obsolete"))
            combined = insert_before(obsolete, "const SCALE = 2\n\n") +
                insert_after(obsolete, "\nfunction replacement_function()\n    return SCALE\nend\n") +
                delete(obsolete)

            @test combined isa Patch
            @test occursin("Patch modifies", show_plain(combined))
            apply!(combined; git=false, yes=true)

            text_after_combined = read("examples/DemoPackage.jl", String)
            @test occursin("const SCALE = 2", text_after_combined)
            @test occursin("function replacement_function()", text_after_combined)
            @test !occursin("function obsolete", text_after_combined)

            renamed = replace(find(ws, "old_function_name"), "old_function_name" => "new_function_name")
            show_plain(renamed)
            apply!(renamed; git=false, yes=true)
            @test occursin("new_function_name", read("examples/DemoPackage.jl", String))

            empty = replace(find(ws, "does_not_exist"), "a" => "b")
            @test occursin("Empty patch", show_plain(empty))
            apply!(empty; git=false, yes=true)

            function_form = patch(
                append_to("examples/notes.txt", "\nAppended note.\n"),
                prepend_to("examples/notes.txt", "Preface.\n\n"),
            )
            @test function_form isa Patch
            show_plain(function_form)
            apply!(function_form; git=false, yes=true)

            notes = read("examples/notes.txt", String)
            @test startswith(notes, "Preface.\n\n")
            @test endswith(notes, "\nAppended note.\n")
        end
    end
end

@testset "file operation patch constructors are safe and explicit" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            mkpath("examples")

            create = create_file("examples/generated.jl", "generated_value() = :ok\n")
            @test create isa Patch
            @test occursin("Patch creates", show_plain(create))
            apply!(create; git=false, yes=true)
            @test read("examples/generated.jl", String) == "generated_value() = :ok\n"

            create_existing = create_file("examples/generated.jl", "replacement() = :bad\n")
            @test !is_valid(create_existing)
            @test_throws Exception apply!(create_existing; git=false, yes=true)
            @test read("examples/generated.jl", String) == "generated_value() = :ok\n"

            move = move_file("examples/generated.jl", "examples/generated-renamed.jl")
            @test occursin("Patch moves", show_plain(move))
            apply!(move; git=false, yes=true)
            @test !ispath("examples/generated.jl")
            @test read("examples/generated-renamed.jl", String) == "generated_value() = :ok\n"

            delete_generated = delete_file("examples/generated-renamed.jl")
            @test occursin("Patch deletes", show_plain(delete_generated))
            apply!(delete_generated; git=false, yes=true)
            @test !ispath("examples/generated-renamed.jl")

            delete_missing = delete_file("examples/missing.jl")
            @test !is_valid(delete_missing)
            @test_throws Exception apply!(delete_missing; git=false, yes=true)
        end
    end
end

@testset "validation rejects invalid final Julia before writing" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            write_demo_workspace(dir)
            ws = workspace("examples"; git=false)

            increment = only(find(ws, "function increment"))
            invalid = replace(increment, "function broken(\n")
            shown = show_plain(invalid)

            @test occursin("Validation errors:", shown)
            @test !is_valid(invalid)
            @test_throws Exception apply!(invalid; git=false, yes=true)
            @test occursin("function increment", read("examples/DemoPackage.jl", String))

            repaired_final_state = patch(
                replace(increment, "function temporarily_broken(\n"),
                replace(increment, "function increment(x)\n    return x + 100\nend\n"),
            )
            show_plain(repaired_final_state)
            @test is_valid(repaired_final_state)
            apply!(repaired_final_state; git=false, yes=true)
            @test occursin("x + 100", read("examples/DemoPackage.jl", String))
        end
    end
end

@testset "git-backed apply, commit alias, precommit, and dirty policy" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            write_demo_workspace(dir)

            run(`git init`)
            run(`git config user.email codeedit@example.invalid`)
            run(`git config user.name CodeEdit`)
            run(`git add examples`)
            run(`git commit -m initial`)

            ws = workspace("examples"; git=:required, review=true)

            increment = only(find(ws, "function increment"))
            p = replace(increment, "x + 1" => "x + 2")
            show_plain(p)
            result = apply!(p, "Change increment"; yes=true)

            @test occursin("x + 2", read("examples/DemoPackage.jl", String))
            @test strip(read(`git log -1 --pretty=%B`, String)) == "Change increment"
            @test isempty(strip(read(`git status --porcelain`, String)))
            @test !isempty(result.changes)
            @test !isempty(result.commits)

            increment = only(find(ws, "function increment"))
            p2 = replace(increment, "x + 2" => "x + 3")
            show_plain(p2)
            commit!(p2, "Commit alias changes increment"; yes=true)

            @test occursin("x + 3", read("examples/DemoPackage.jl", String))
            @test strip(read(`git log -1 --pretty=%B`, String)) == "Commit alias changes increment"
            @test isempty(strip(read(`git status --porcelain`, String)))

            write("examples/DemoPackage.jl", replace(read("examples/DemoPackage.jl", String), "x + 3" => "x + 4"))
            dirty_block = only(find(ws, "function increment"))
            dirty_patch = replace(dirty_block, "x + 4" => "x + 5")
            show_plain(dirty_patch)

            @test_throws Exception apply!(dirty_patch, "Reject dirty file"; yes=true)
            @test occursin("x + 4", read("examples/DemoPackage.jl", String))
            @test strip(read(`git log -1 --pretty=%B`, String)) == "Commit alias changes increment"

            apply!(dirty_patch, "Apply after precommit"; precommit="Checkpoint dirty work", yes=true, require_clean=false)
            @test occursin("x + 5", read("examples/DemoPackage.jl", String))
            @test split(strip(read(`git log --pretty=%B -2`, String)), "\n\n") == [
                "Apply after precommit",
                "Checkpoint dirty work",
            ]
            @test isempty(strip(read(`git status --porcelain`, String)))
        end
    end
end

@testset "explicit non-git writes and non-git error guidance" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            write("scratch.txt", "temporary = false\n")

            scratch = block("scratch.txt:1"; as=:text)
            p = replace(scratch, "false" => "true")
            show_plain(p)

            err = try
                apply!(p; yes=true)
                nothing
            catch e
                e
            end
            @test err !== nothing
            @test occursin("git=false", sprint(showerror, err))
            @test read("scratch.txt", String) == "temporary = false\n"

            apply!(p; git=false, yes=true)
            @test read("scratch.txt", String) == "temporary = true\n"
        end
    end
end

@testset "stacktraces and methods resolve to editable blocks" begin
    CodeEdit.clear_cache!()

    mktempdir() do dir
        cd(dir) do
            write_demo_workspace(dir)
            ws = workspace("examples"; git=false)

            Base.invokelatest(include, joinpath(dir, "examples", "error-example.jl"))
            outer_ref = getfield(@__MODULE__, :outer)

            trace = try
                Base.invokelatest(outer_ref, 1)
            catch
                stacktrace(catch_backtrace())
            end

            trace_blocks = blocks(trace; in=ws)
            @test trace_blocks isa AbstractVector
            @test any(b -> occursin("function inner", source(b)), trace_blocks)
            @test any(b -> occursin("function outer", source(b)), trace_blocks)

            error_block = only(find(trace_blocks, "error("))
            p = replace(
                error_block,
                "error(\"bad input: \$x\")" => "throw(ArgumentError(\"bad input: \$x\"))",
            )
            show_plain(p)
            apply!(p; git=false, yes=true)
            @test occursin("throw(ArgumentError", read("examples/error-example.jl", String))

            Base.invokelatest(include, joinpath(dir, "examples", "DemoPackage.jl"))
            increment_ref = getfield(getfield(@__MODULE__, :DemoPackage), :increment)
            method_block = block(first(methods(increment_ref)))
            @test occursin("function increment", source(method_block))

            method_patch = edit(first(methods(increment_ref)), "x + 1" => "x + 2")
            @test method_patch isa Patch
            @test occursin("Patch modifies", show_plain(method_patch))
        end
    end
end
