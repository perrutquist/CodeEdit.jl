using LibGit2

@testset "version control apply API" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            write("foo.jl", """
            function foo()
                1
            end
            """)

            edit = Replace(Handle("foo.jl", 1), """
            function foo()
                2
            end
            """)

            @test_throws ErrorException apply!(edit)

            display_text = sprint(show, MIME"text/plain"(), edit)
            @test occursin("Edit modifies", display_text)

            apply!(NoVersionControl(require_view=true), edit)
            @test occursin("2", read("foo.jl", String))
        end
    end
end

@testset "git apply commits edits" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            run(`git init`)
            run(`git config user.email codeedit@example.invalid`)
            run(`git config user.name CodeEdit`)

            write("foo.jl", """
            function foo()
                1
            end
            """)

            run(`git add foo.jl`)
            run(`git commit -m initial`)

            edit = Replace(Handle("foo.jl", 1), """
            function foo()
                3
            end
            """)

            repo = VersionControl(".")
            apply!(repo, edit, "Change foo return value")

            @test occursin("3", read("foo.jl", String))
            @test strip(read(`git log -1 --pretty=%B`, String)) == "Change foo return value"
            @test isempty(strip(read(`git status --porcelain`, String)))
        end
    end
end

@testset "git apply can create versioned files" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            run(`git init`)
            run(`git config user.email codeedit@example.invalid`)
            run(`git config user.name CodeEdit`)
            write("README.md", "initial\n")
            run(`git add README.md`)
            run(`git commit -m initial`)

            edit = CreateFile("created.jl", "created() = true\n")
            apply!(VersionControl("."), edit, "Create new file")

            @test read("created.jl", String) == "created() = true\n"
            @test strip(read(`git log -1 --pretty=%B`, String)) == "Create new file"
            @test strip(read(`git ls-files created.jl`, String)) == "created.jl"
        end
    end
end
