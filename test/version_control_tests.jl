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

@testset "git apply requires displayed edit when configured" begin
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
                4
            end
            """)

            repo = VersionControl(".", require_view=true)
            @test_throws Exception apply!(repo, edit, "Change without viewing")
            @test occursin("1", read("foo.jl", String))

            display_text = sprint(show, MIME"text/plain"(), edit)
            @test occursin("Edit modifies", display_text)

            apply!(repo, edit, "Change after viewing")
            @test occursin("4", read("foo.jl", String))
            @test strip(read(`git log -1 --pretty=%B`, String)) == "Change after viewing"
        end
    end
end

@testset "git apply uses default commit message" begin
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
                5
            end
            """)

            apply!(VersionControl(".", default_message="Use configured message"), edit)

            @test occursin("5", read("foo.jl", String))
            @test strip(read(`git log -1 --pretty=%B`, String)) == "Use configured message"
            @test isempty(strip(read(`git status --porcelain`, String)))
        end
    end
end

@testset "git apply rejects dirty tracked files by default" begin
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

            write("foo.jl", """
            function foo()
                2
            end
            """)

            edit = Replace(Handle("foo.jl", 1), """
            function foo()
                6
            end
            """)

            @test_throws Exception apply!(VersionControl("."), edit, "Change dirty file")
            @test occursin("2", read("foo.jl", String))
            @test strip(read(`git log -1 --pretty=%B`, String)) == "initial"
            @test !isempty(strip(read(`git status --porcelain`, String)))
        end
    end
end

@testset "git apply can precommit dirty tracked files" begin
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

            write("foo.jl", """
            function foo()
                2
            end
            """)

            edit = Replace(Handle("foo.jl", 1), """
            function foo()
                7
            end
            """)

            repo = VersionControl(".", precommit_message="Save dirty tracked file")
            apply!(repo, edit, "Apply requested edit")

            @test occursin("7", read("foo.jl", String))
            @test split(strip(read(`git log --pretty=%B -2`, String)), "\n\n") == [
                "Apply requested edit",
                "Save dirty tracked file",
            ]
            @test isempty(strip(read(`git status --porcelain`, String)))
        end
    end
end

@testset "git apply rejects edits to untracked files when versioning is required" begin
    mktempdir() do dir
        cd(dir) do
            CodeEdit.clear_cache!()

            run(`git init`)
            run(`git config user.email codeedit@example.invalid`)
            run(`git config user.name CodeEdit`)

            write("README.md", "initial\n")
            run(`git add README.md`)
            run(`git commit -m initial`)

            write("scratch.jl", """
            function scratch()
                1
            end
            """)

            edit = Replace(Handle("scratch.jl", 1), """
            function scratch()
                8
            end
            """)

            @test_throws Exception apply!(VersionControl("."), edit, "Modify untracked file")
            @test occursin("1", read("scratch.jl", String))
            @test strip(read(`git log -1 --pretty=%B`, String)) == "initial"
            @test occursin("?? scratch.jl", read(`git status --porcelain`, String))
        end
    end
end
