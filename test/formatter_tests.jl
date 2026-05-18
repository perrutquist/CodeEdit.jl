using JuliaFormatter

@testset "formatter updates handles after preformatting changes line numbers" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            write("sample.jl", """
            function before();1+2;end
            function target(x);x+1;end
            function after();3;end
            """)

            target = Handle("sample.jl", 2)
            after = Handle("sample.jl", 3)
            @test first(lines(after)) == 3

            edit = Replace(target, """
            function target(x)
            x+2
            end
            """)

            apply!(NoVersionControl(formatter=JuliaFormatter.format_text), edit)

            text = read("sample.jl", String)
            @test occursin("function before()", text)
            @test occursin("1 + 2", text)
            @test occursin("function target(x)", text)
            @test occursin("x + 2", text)
            @test !occursin("x + 1", text)

            @test is_valid(after)
            @test occursin("function after()", string(after))
            @test first(lines(after)) > 3
        end
    end
end

@testset "formatter preserves unrelated handles while editing later blocks" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            write("sample.jl", """
            function prefix();1;end
            function watched(y);y*2;end
            function target();3;end
            """)

            watched = Handle("sample.jl", 2)
            target = Handle("sample.jl", 3)

            edit = Replace(target, """
            function target()
            4
            end
            """)

            apply!(NoVersionControl(formatter=JuliaFormatter.format_text), edit)

            text = read("sample.jl", String)
            @test occursin("function watched(y)", text)
            @test occursin("y * 2", text)
            @test occursin("function target()", text)
            @test occursin("4", text)

            @test is_valid(watched)
            @test occursin("function watched(y)", string(watched))
            @test occursin("y * 2", string(watched))
            @test first(lines(watched)) > 2
        end
    end
end

@testset "formatter keeps InsertBefore target valid after line shifts" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            write("sample.jl", """
            function prefix();1;end
            function marker();2;end
            """)

            marker = Handle("sample.jl", 2)
            edit = InsertBefore(marker, "function inserted();3;end\n")

            apply!(NoVersionControl(formatter=JuliaFormatter.format_text), edit)

            text = read("sample.jl", String)
            inserted_range = findfirst("function inserted()", text)
            marker_range = findfirst("function marker()", text)

            @test inserted_range !== nothing
            @test marker_range !== nothing
            @test first(inserted_range) < first(marker_range)

            @test is_valid(marker)
            @test occursin("function marker()", string(marker))
            @test first(lines(marker)) > 2
        end
    end
end

@testset "formatter deletes the intended block after preformatting" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            write("sample.jl", """
            function prefix();1;end
            function victim();2;end
            function survivor();3;end
            """)

            victim = Handle("sample.jl", 2)
            survivor = Handle("sample.jl", 3)

            apply!(NoVersionControl(formatter=JuliaFormatter.format_text), Delete(victim))

            text = read("sample.jl", String)
            @test occursin("function prefix()", text)
            @test !occursin("function victim()", text)
            @test occursin("function survivor()", text)

            @test !is_valid(victim)
            @test is_valid(survivor)
            @test occursin("function survivor()", string(survivor))
            @test first(lines(survivor)) > 3
        end
    end
end

@testset "formatter supports combined edits after reindexing" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            write("sample.jl", """
            function prefix();1;end
            function first_target();2;end
            function second_target();3;end
            """)

            first_target = Handle("sample.jl", 2)
            second_target = Handle("sample.jl", 3)

            edit = Combine(
                Replace(first_target, """
                function first_target()
                20
                end
                """),
                InsertAfter(second_target, "function inserted_after();4;end\n"),
            )

            apply!(NoVersionControl(formatter=JuliaFormatter.format_text), edit)

            text = read("sample.jl", String)
            @test occursin("function first_target()", text)
            @test occursin("20", text)
            @test occursin("function second_target()", text)
            @test occursin("function inserted_after()", text)

            @test is_valid(second_target)
            @test occursin("function second_target()", string(second_target))
            @test first(lines(second_target)) > 3
        end
    end
end
