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
end
