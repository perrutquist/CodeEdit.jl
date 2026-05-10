using CodeEdit
using Test

@testset "CodeEdit.jl" begin
    @testset "spans" begin
        text = "αβ\nx\r\ny"
        starts = CodeEdit.build_line_starts(text)

        @test starts == [1, 6, 9]
        @test CodeEdit.line_count(starts) == 3
        @test CodeEdit.span_text(text, CodeEdit.line_content_span(text, starts, 1)) == "αβ"
        @test CodeEdit.line_char_count(text, starts, 1) == 2
        @test CodeEdit.byte_offset_for_line_pos(text, starts, 1, 2) == nextind(text, 1)
        @test CodeEdit.eof_line(text, starts) == 4
        @test CodeEdit.detect_line_ending("a\r\nb\r\nc\n") == "\r\n"
        @test CodeEdit.detect_line_ending("a\nb\r\n") == "\n"
    end

    @testset "text parsing" begin
        text = "first paragraph\nstill first\n\nsecond\n"
        blocks = CodeEdit.parse_text_blocks(text)

        @test length(blocks) == 3
        @test blocks[1].kind == :text
        @test blocks[1].lines == 1:2
        @test blocks[2].lines == 4:4
        @test blocks[3].kind == :eof
    end

    @testset "JuliaSyntax parsing" begin
        text = "module M\n# attached\nf(x) = x\n\nconst y = 1\nend\n"
        blocks = CodeEdit.parse_julia_blocks(text)

        @test length(blocks) == 5
        @test blocks[1].kind == :module_header
        @test blocks[1].lines == 1:1
        @test blocks[2].kind == :julia
        @test blocks[2].lines == 2:3
        @test blocks[3].kind == :julia
        @test blocks[3].lines == 5:5
        @test blocks[4].kind == :module_footer
        @test blocks[4].lines == 6:6
        @test blocks[5].kind == :eof

        same_line = CodeEdit.parse_julia_blocks("x = 1; y = 2\n")
        @test length(same_line) == 2
        @test same_line[1].kind == :julia
        @test same_line[1].lines == 1:1
        @test same_line[2].kind == :eof
    end

    @testset "file loading, handles, display, and search" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "sample.jl")
            write(path, """
            function foo(x)
                x + 1
            end

            y = foo(1)
            """)

            hs = handles(path)
            @test length(hs) == 3

            h = Handle(path, 2)
            @test is_valid(h)
            @test filepath(h) == path
            @test lines(h) == 1:3
            @test occursin("function foo", string(h))
            @test docstring(h) === nothing

            same = Handle(path, 1)
            @test h === same

            eof = eof_handle(path)
            @test is_valid(eof)
            @test lines(eof) == 6:6
            @test string(eof) == ""

            shown = sprint(show, MIME"text/plain"(), h)
            @test occursin("# $path 1 - 3:", shown)
            @test occursin("function foo", shown)

            found = search(path, "foo(1)")
            @test length(found) == 1
            @test only(found) === Handle(path, 5)
        end
    end

    @testset "text handles" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "notes.txt")
            write(path, "alpha\n\nbeta\n")

            h = Handle(path, 2; parse_as=:text)
            @test string(h) == "beta\n"
            @test lines(h) == 3:3
            @test eof_handle(path; parse_as=:text) in handles(path; parse_as=:text)
        end
    end

    @testset "edit constructors" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "edit.jl")
            write(path, "x = 1\n")

            h = Handle(path, 1)
            replace = Replace(h, "x = 2\n")
            delete = Delete(h)
            before = InsertBefore(h, "# before\n")
            after = InsertAfter(h, "# after\n")
            create = CreateFile(joinpath(dir, "new.jl"), "y = 1\n")
            move = MoveFile(path, joinpath(dir, "moved.jl"))
            delete_file = DeleteFile(path)
            combined = replace * delete

            @test replace.handle === h
            @test replace.code == "x = 2\n"
            @test delete.handle === h
            @test before.code == "# before\n"
            @test after.code == "# after\n"
            @test create.parse_as == :auto
            @test move.old_path == path
            @test delete_file.path == path
            @test combined isa Combine
            @test length(combined.edits) == 2
            @test is_valid(combined)

            @test replace.displayed[] === nothing
            displayed!(replace, true)
            @test replace.displayed[] !== nothing
            displayed!(replace, false)
            @test replace.displayed[] === nothing
        end
    end

    @testset "single edit display, validation, apply, and cache update" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "apply.jl")
            write(path, """
            function first()
                1
            end

            function second()
                2
            end
            """)

            first = Handle(path, 1)
            second = Handle(path, 5)

            edit = Replace(first, replace(string(first), "1" => "10"))
            shown = sprint(show, MIME"text/plain"(), edit)

            @test occursin("Edit modifies", shown)
            @test occursin("<", shown)
            @test occursin(">", shown)
            @test edit.displayed[] !== nothing
            @test is_valid(edit)

            apply!(edit)

            @test read(path, String) == """
            function first()
                10
            end

            function second()
                2
            end
            """
            @test is_valid(first)
            @test occursin("10", string(first))
            @test is_valid(second)
            @test lines(second) == 5:7
        end

        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "insert.jl")
            write(path, """
            function first()
                1
            end

            function second()
                2
            end
            """)

            second = Handle(path, 5)
            edit = InsertBefore(second, "const inserted = 1\n\n")
            displayed!(edit)
            apply!(edit)

            @test read(path, String) == """
            function first()
                1
            end

            const inserted = 1

            function second()
                2
            end
            """
            @test is_valid(second)
            @test lines(second) == 7:9
            @test occursin("function second", string(second))
        end

        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "delete.jl")
            write(path, """
            x = 1

            y = 2
            """)

            x = Handle(path, 1)
            y = Handle(path, 3)
            @test lines(y) == 3:3
            edit = Delete(x)
            displayed!(edit)
            apply!(edit)

            @test !is_valid(x)
            @test is_valid(y)
            @test lines(y) == 2:2 # location updated after code was removed
            @test read(path, String) == """
            
            y = 2
            """
        end
    end

    @testset "single edit safety failures" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "invalid.jl")
            write(path, "x = 1\n")

            h = Handle(path, 1)
            edit = Replace(h, "function broken(\n")
            shown = sprint(show, MIME"text/plain"(), edit)

            @test occursin("Validation errors:", shown)
            @test !is_valid(edit)
            @test edit.displayed[] !== nothing
            @test_throws ErrorException apply!(edit)
            @test read(path, String) == "x = 1\n"
        end

        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "changed.jl")
            write(path, "x = 1\n")
            sleep(1.1)

            h = Handle(path, 1)
            edit = Replace(h, "x = 2\n")
            displayed!(edit)
            write(path, "x = 3\n")

            @test_throws ErrorException apply!(edit)
            @test read(path, String) == "x = 3\n"
        end

        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "undisplayed.jl")
            write(path, "x = 1\n")

            h = Handle(path, 1)
            edit = Replace(h, "x = 2\n")

            @test_throws ErrorException apply!(edit)
            @test read(path, String) == "x = 1\n"
        end
    end

    @testset "docstrings, recursive includes, method handles, and stacktrace search" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            child = joinpath(dir, "child.jl")
            parent = joinpath(dir, "parent.jl")

            write(child, """
            "child doc"
            child_function() = error("boom")
            """)
            write(parent, """
            include("child.jl")

            parent_function() = child_function()
            """)

            hs = handles(parent; includes=true)
            @test any(h -> occursin("child_function", string(h)), hs)

            child_handle = only(search(hs, "child_function() = error"))
            @test docstring(child_handle) == "child doc"

            Base.invokelatest(include, parent)
            parent_function_ref = getfield(@__MODULE__, :parent_function)
            method_handle = Handle(first(methods(parent_function_ref)))
            @test occursin("parent_function", string(method_handle))

            trace = try
                Base.invokelatest(parent_function_ref)
            catch
                catch_backtrace()
            end

            found = search(hs, trace)
            @test any(h -> occursin("child_function", string(h)), found)
        end
    end

    @testset "ordered Combine planning and apply" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "combine.jl")
            write(path, """
            x = 1

            y = 2
            """)

            x = Handle(path, 1)
            y = Handle(path, 3)
            edit = Combine(InsertBefore(y, "z = 3\n\n"), Replace(y, "y = 20\n"))
            displayed!(edit)
            apply!(edit)

            @test read(path, String) == """
            x = 1

            z = 3

            y = 20
            """
            @test is_valid(y)
            @test lines(y) == 5:5
            @test occursin("y = 20", string(y))
            @test is_valid(x)
        end

        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "moveblock.jl")
            write(path, """
            a = 1

            b = 2
            """)

            a = Handle(path, 1)
            b = Handle(path, 3)
            edit = Combine(InsertBefore(b, string(a) * "\n"), Delete(a))
            displayed!(edit)
            apply!(edit)

            @test read(path, String) == """
            
            a = 1

            b = 2
            """
            @test !is_valid(a)
            @test is_valid(b)
        end
    end

    @testset "file create, move, delete, and cache updates" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            created = joinpath(dir, "created.jl")
            moved = joinpath(dir, "moved.jl")

            create = CreateFile(created, "created_value = 1\n")
            displayed!(create)
            apply!(create)

            @test read(created, String) == "created_value = 1\n"
            @test length(search(created, "created_value")) == 1

            h = Handle(created, 1)
            edit = Combine(MoveFile(created, moved), Replace(h, "created_value = 2\n"))
            displayed!(edit)
            apply!(edit)

            @test !ispath(created)
            @test read(moved, String) == "created_value = 2\n"
            @test is_valid(h)
            @test filepath(h) == moved

            delete = DeleteFile(moved)
            displayed!(delete)
            apply!(delete)

            @test !ispath(moved)
            @test !is_valid(h)
        end
    end

    @testset "external reindexing" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "reindex.jl")
            write(path, """
            first = 1

            second = 2
            """)

            first = Handle(path, 1)
            second = Handle(path, 3)

            write(path, """
            inserted = 0

            first = 1

            second = 2
            """)

            reindex(path)

            @test is_valid(first)
            @test is_valid(second)
            @test lines(first) == 3:3
            @test lines(second) == 5:5
        end
    end

    @testset "deleted and recreated files do not reuse stale invalid handles" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "recreated.jl")
            write(path, "original_value = 1\n")

            original = Handle(path, 1)
            @test is_valid(original)

            rm(path)
            @test !is_valid(original)

            write(path, "recreated_value = 2\n")
            recreated = Handle(path, 1)

            @test is_valid(recreated)
            @test occursin("recreated_value = 2", string(recreated))
            @test !is_valid(original)
        end
    end

    @testset "automatic external reindexing" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "automatic_reindex.jl")
            write(path, """
            first = 1

            second = 2
            """)

            first = Handle(path, 1)
            second = Handle(path, 3)

            write(path, """
            inserted = 0

            first = 10

            second = 20
            """)

            @test is_valid(first)
            @test is_valid(second)
            @test lines(first) == 3:3
            @test lines(second) == 5:5
            @test occursin("first = 10", string(first))
            @test occursin("second = 20", string(second))
        end
    end

    @testset "handle positions, bounds, and next-block selection" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "positions.jl")
            write(path, """
            αβ = 1

            γδ = 2
            """)

            first = Handle(path, 1, 2)
            next = Handle(path, 2, 1)

            @test lines(first) == 1:1
            @test occursin("αβ = 1", string(first))
            @test lines(next) == 3:3
            @test occursin("γδ = 2", string(next))
            @test_throws ArgumentError Handle(path, 0)
            @test_throws ArgumentError Handle(path, 5)
            @test_throws ArgumentError Handle(path, 1, 0)
            @test_throws ArgumentError Handle(path, 1, 100)
        end
    end

    @testset "invalid UTF-8 and parse mode invalidation" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            invalid = joinpath(dir, "invalid_utf8.jl")
            write(invalid, UInt8[0xff, 0xfe, 0xfd])

            @test_throws ArgumentError handles(invalid)

            path = joinpath(dir, "mode_switch.jl")
            write(path, """
            alpha

            beta
            """)

            text_handle = Handle(path, 1; parse_as=:text)
            @test is_valid(text_handle)
            @test lines(text_handle) == 1:1

            julia_handle = Handle(path, 1; parse_as=:julia)
            @test is_valid(julia_handle)
            @test !is_valid(text_handle)
        end
    end

    @testset "path identity and display path retention" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "same.jl")
            link = joinpath(dir, "same_link.jl")
            write(path, "same_value = 1\n")
            symlink(path, link)

            cd(dir) do
                relative = Handle("same.jl", 1)
                absolute = Handle(path, 1)
                linked = Handle(link, 1)

                @test relative === absolute
                @test relative === linked
                @test filepath(relative) == "same.jl"
                @test occursin("# same.jl 1 - 1:", sprint(show, MIME"text/plain"(), relative))
            end
        end
    end

    @testset "directory, glob, and vector overloads" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            first = joinpath(dir, "first.jl")
            second = joinpath(dir, "second.jl")
            ignored = joinpath(dir, "ignored.txt")

            write(first, "first_value = 1\n")
            write(second, "second_value = 2\n")
            write(ignored, "first_value in text\n")

            from_vector = handles([first, second])
            from_glob = handles(dir, "*.jl")

            @test length(search(from_vector, "first_value")) == 1
            @test length(search(from_vector, "second_value")) == 1
            @test length(search([first, second], "second_value")) == 1
            @test length(search(dir, "*.jl", "first_value")) == 1
            @test all(h -> endswith(filepath(h), ".jl"), from_glob)
        end
    end

    @testset "recursive includes with cycles" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            a = joinpath(dir, "a.jl")
            b = joinpath(dir, "b.jl")
            c = joinpath(dir, "c.jl")

            write(a, """
            include("b.jl")
            a_function() = 1
            """)
            write(b, """
            include("c.jl")
            b_function() = 2
            """)
            write(c, """
            include("a.jl")
            c_function() = 3
            """)

            hs = handles(a; includes=true)

            @test length(search(hs, "a_function")) == 1
            @test length(search(hs, "b_function")) == 1
            @test length(search(hs, "c_function")) == 1
        end
    end

    @testset "Julia block taxonomy" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            child = joinpath(dir, "taxonomy_child.jl")
            path = joinpath(dir, "taxonomy.jl")

            write(child, "child_value = 1\n")
            write(path, """
            using Test
            import Base: show
            export documented_function

            const taxonomy_const = 1

            struct TaxonomyStruct
                x::Int
            end

            mutable struct MutableTaxonomyStruct
                x::Int
            end

            macro taxonomy_macro()
                return :(1)
            end

            "documented function"
            function documented_function(x)
                x + 1
            end

            multiline_assignment = begin
                1
            end

            include("taxonomy_child.jl")
            """)

            hs = handles(path)

            @test length(search(hs, "using Test")) == 1
            @test length(search(hs, "import Base")) == 1
            @test length(search(hs, "export documented_function")) == 1
            @test length(search(hs, "taxonomy_const")) == 1
            @test length(search(hs, "struct TaxonomyStruct")) == 1
            @test length(search(hs, "mutable struct MutableTaxonomyStruct")) == 1
            @test length(search(hs, "macro taxonomy_macro")) == 1
            @test length(search(hs, "function documented_function")) == 1
            @test length(search(hs, "multiline_assignment")) == 1
            @test length(search(hs, "include(\"taxonomy_child.jl\")")) == 1
            @test docstring(only(search(hs, "function documented_function"))) == "documented function"
            @test length(search(path, "child_value")) == 0
            @test length(search(handles(path; includes=true), "child_value")) == 1
        end
    end

    @testset "display variants and occursin stacktrace search" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            path = joinpath(dir, "display_and_trace.jl")
            write(path, """
            traced_function() = error("trace boom")

            other_function() = 1
            """)

            hs = handles(path)
            traced = only(search(hs, "traced_function"))
            other = only(search(hs, "other_function"))

            @test occursin("traced_function", sprint(show, MIME"text/plain"(), [traced]))
            @test occursin("2 handles", sprint(show, MIME"text/plain"(), Set([traced, other])))

            Base.invokelatest(include, path)
            traced_ref = getfield(@__MODULE__, :traced_function)

            trace = try
                Base.invokelatest(traced_ref)
            catch
                catch_backtrace()
            end

            @test occursin(traced, trace)
            @test !occursin(other, trace)
            @test traced in search(hs, trace)

            deleteat!(Base.LOAD_PATH, findall(==(dir), Base.LOAD_PATH))
        end
    end

    @testset "edit display paths and Revise callback hook" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            string_path = joinpath(dir, "string_display.jl")
            display_path = joinpath(dir, "base_display.jl")
            callback_path = joinpath(dir, "callback.jl")

            write(string_path, "x = 1\n")
            write(display_path, "y = 1\n")
            write(callback_path, "z = 1\n")

            string_edit = Replace(Handle(string_path, 1), "x = 2\n")
            @test string_edit.displayed[] === nothing
            @test occursin("Edit modifies", string(string_edit))
            @test string_edit.displayed[] !== nothing

            display_edit = Replace(Handle(display_path, 1), "y = 2\n")
            @test display_edit.displayed[] === nothing
            display(display_edit)
            @test display_edit.displayed[] !== nothing

            calls = Ref(0)
            old_callback = CodeEdit._maybe_revise_callback[]
            try
                CodeEdit._maybe_revise_callback[] = () -> (calls[] += 1; nothing)
                callback_edit = Replace(Handle(callback_path, 1), "z = 2\n")
                displayed!(callback_edit)
                apply!(callback_edit)

                @test calls[] == 1
            finally
                CodeEdit._maybe_revise_callback[] = old_callback
            end
        end
    end

    @testset "file operation safety edge cases" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            existing = joinpath(dir, "existing.jl")
            destination = joinpath(dir, "destination.jl")
            missing = joinpath(dir, "missing.jl")
            source = joinpath(dir, "source.jl")
            link = joinpath(dir, "source_link.jl")
            text_file = joinpath(dir, "created_text.txt")

            write(existing, "existing_value = 1\n")
            write(destination, "destination_value = 1\n")
            write(source, "source_value = 1\n")
            symlink(source, link)

            create_existing = CreateFile(existing, "replacement = 1\n")
            displayed!(create_existing)
            @test !is_valid(create_existing)
            @test_throws ErrorException apply!(create_existing)

            create_invalid = CreateFile(joinpath(dir, "invalid_created.jl"), "function broken(\n"; parse_as=:julia)
            shown = sprint(show, MIME"text/plain"(), create_invalid)
            @test occursin("Validation errors:", shown)
            @test !is_valid(create_invalid)
            @test_throws ErrorException apply!(create_invalid)

            create_text = CreateFile(text_file, "function broken(\n"; parse_as=:text)
            displayed!(create_text)
            @test is_valid(create_text)
            apply!(create_text)
            @test read(text_file, String) == "function broken(\n"

            move_to_existing = MoveFile(source, destination)
            displayed!(move_to_existing)
            @test !is_valid(move_to_existing)
            @test_throws ErrorException apply!(move_to_existing)

            move_missing = MoveFile(missing, joinpath(dir, "moved_missing.jl"))
            displayed!(move_missing)
            @test !is_valid(move_missing)
            @test_throws ErrorException apply!(move_missing)

            delete_missing = DeleteFile(missing)
            displayed!(delete_missing)
            @test !is_valid(delete_missing)
            @test_throws ErrorException apply!(delete_missing)

            move_symlink = MoveFile(link, joinpath(dir, "moved_link.jl"))
            displayed!(move_symlink)
            @test !is_valid(move_symlink)
            @test_throws ErrorException apply!(move_symlink)

            delete_symlink = DeleteFile(link)
            displayed!(delete_symlink)
            @test !is_valid(delete_symlink)
            @test_throws ErrorException apply!(delete_symlink)
            @test ispath(link)
            @test ispath(source)
        end
    end

    @testset "combined edits across files and final validation" begin
        CodeEdit.clear_cache!()

        mktempdir() do dir
            first_path = joinpath(dir, "combined_first.jl")
            second_path = joinpath(dir, "combined_second.jl")
            write(first_path, "first_value = 1\n")
            write(second_path, "second_value = 2\n")

            first = Handle(first_path, 1)
            second = Handle(second_path, 1)
            edit = Combine(
                Replace(first, "first_value = 10\n"),
                Replace(second, "second_value = 20\n"),
            )
            displayed!(edit)
            apply!(edit)

            @test read(first_path, String) == "first_value = 10\n"
            @test read(second_path, String) == "second_value = 20\n"
            @test is_valid(first)
            @test is_valid(second)
            @test occursin("10", string(first))
            @test occursin("20", string(second))

            invalid = Combine(
                Replace(first, "function broken(\n"),
                Replace(second, "second_value = 30\n"),
            )
            shown = sprint(show, MIME"text/plain"(), invalid)
            @test occursin("Validation errors:", shown)
            @test !is_valid(invalid)
            @test_throws ErrorException apply!(invalid)
            @test read(first_path, String) == "first_value = 10\n"
            @test read(second_path, String) == "second_value = 20\n"
        end
    end
end
