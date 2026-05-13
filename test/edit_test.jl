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
