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
