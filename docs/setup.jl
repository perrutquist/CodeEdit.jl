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
