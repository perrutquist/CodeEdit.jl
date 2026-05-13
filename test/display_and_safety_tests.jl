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
            apply!(NoVersionControl(), callback_edit)

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
        @test_throws ErrorException apply!(NoVersionControl(), create_existing)

        create_invalid = CreateFile(joinpath(dir, "invalid_created.jl"), "function broken(\n"; parse_as=:julia)
        shown = sprint(show, MIME"text/plain"(), create_invalid)
        @test occursin("Validation errors:", shown)
        @test !is_valid(create_invalid)
        @test_throws ErrorException apply!(NoVersionControl(), create_invalid)

        create_text = CreateFile(text_file, "function broken(\n"; parse_as=:text)
        @test is_valid(create_text)
        apply!(NoVersionControl(), create_text)
        @test read(text_file, String) == "function broken(\n"

        move_to_existing = MoveFile(source, destination)
        @test !is_valid(move_to_existing)
        @test_throws ErrorException apply!(NoVersionControl(), move_to_existing)

        move_missing = MoveFile(missing, joinpath(dir, "moved_missing.jl"))
        @test !is_valid(move_missing)
        @test_throws ErrorException apply!(NoVersionControl(), move_missing)

        delete_missing = DeleteFile(missing)
        @test !is_valid(delete_missing)
        @test_throws ErrorException apply!(NoVersionControl(), delete_missing)

        move_symlink = MoveFile(link, joinpath(dir, "moved_link.jl"))
        @test !is_valid(move_symlink)
        @test_throws ErrorException apply!(NoVersionControl(), move_symlink)

        delete_symlink = DeleteFile(link)
        @test !is_valid(delete_symlink)
        @test_throws ErrorException apply!(NoVersionControl(), delete_symlink)
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
        apply!(NoVersionControl(), edit)

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
        @test_throws ErrorException apply!(NoVersionControl(), invalid)
        @test read(first_path, String) == "first_value = 10\n"
        @test read(second_path, String) == "second_value = 20\n"
    end
end
