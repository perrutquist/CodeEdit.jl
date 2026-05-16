using Documenter
using CodeEdit

DocMeta.setdocmeta!(
    CodeEdit,
    :DocTestSetup,
    quote
        using CodeEdit

        if !@isdefined(CodeEditDocs)
            module CodeEditDocs
            export ensure_examples!

            function writefile(path::AbstractString, contents::AbstractString)
                mkpath(dirname(path))
                write(path, contents)
            end

            run_quiet(cmd) = run(pipeline(cmd; stdout=devnull, stderr=devnull))

            function ensure_examples!()
                isdir("examples/.git") && return nothing

                rm("examples"; recursive=true, force=true)
                mkpath("examples")

                writefile("examples/foo.jl", """
                function foo(x)
                    x + 1
                end
                """)

                writefile("examples/ProjectCode.jl", """
                module ProjectCode

                const DEFAULT_LIMIT = 10

                function foo(x)
                    return x + 1
                end

                function helper(x)
                    return foo(x) * 2
                end

                function obsolete()
                    return :remove_me
                end

                end
                """)

                writefile("examples/notes.txt", """
                First note.

                Second note.
                """)

                writefile("examples/helpers.jl", """
                helper(x) = x + 1
                """)

                writefile("examples/MyPackage.jl", """
                module MyPackage

                include("helpers.jl")

                const DEFAULT_LIMIT = 10

                function foo(x)
                    y = helper(x)
                    z = y * 2
                    return z
                end

                function old_function_name()
                    return foo(1)
                end

                end
                """)

                writefile("examples/concepts.jl", """
                function foo(x)
                    return x + 1
                end

                function bar(x)
                    return foo(x)
                end
                """)

                writefile("examples/concepts-notes.txt", """
                First paragraph.

                Second paragraph.
                """)

                writefile("examples/error-example.jl", raw"""
                function inner(x)
                    error("bad input: $x")
                end

                function outer(x)
                    return inner(x + 1)
                end
                """)

                writefile("examples/safety.jl", """
                const SAFETY_VALUE = 1
                """)

                run_quiet(`git init examples`)
                run_quiet(`git -C examples config user.email docs@example.com`)
                run_quiet(`git -C examples config user.name "CodeEdit Docs"`)
                run_quiet(`git -C examples add .`)
                run_quiet(`git -C examples commit -m "Initial shared examples"`)

                sleep(1.1)
                return nothing
            end

            end
        end

        CodeEditDocs.ensure_examples!()
        include("examples/error-example.jl")
    end;
    recursive=true,
)

DocMeta.setdocmeta!(
    CodeEdit,
    :DocTestFilters,
    [r"/[0-9a-zA-Z/]*/examples", r"main [0-9a-f]*", r"commit [0-9a-f]*"];
    recursive=true,
)

basedir = mktempdir()

makedocs(
    sitename = "CodeEdit.jl",
    modules = [CodeEdit],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
    ),
    pages = [
        "Home" => "index.md",
        "Getting started" => "getting-started.md",
        "Blocks and handles" => "concepts.md",
        "Editing code" => "editing.md",
        "Safety and version control" => "safety.md",
        "Finding errors from stacktraces" => "searching-errors.md",
        "API reference" => "api.md",
    ],
    checkdocs = :none,
    workdir = basedir,
)

function clean_generated_html_paths(builddir::AbstractString, basedir::AbstractString)
    prefixes = [basedir]
    real_basedir = realpath(basedir)

    if real_basedir != basedir
        push!(prefixes, real_basedir)
    end
    sort!(prefixes, by=length, rev=true)

    for (root, _, files) in walkdir(builddir)
        for file in files
            endswith(file, ".html") || continue

            path = joinpath(root, file)
            contents = read(path, String)
            cleaned = contents

            for prefix in prefixes
                cleaned = replace(cleaned, prefix * "/" => "")
            end

            if cleaned != contents
                write(path, cleaned)
            end
        end
    end
end

clean_generated_html_paths(joinpath(@__DIR__, "build"), basedir)

if get(ENV, "CI", "false") == "true" && haskey(ENV, "GITHUB_REPOSITORY")
    deploydocs(
        repo = "github.com/$(ENV["GITHUB_REPOSITORY"]).git",
        push_preview = true,
    )
end
