using CodeEdit

if !@isdefined(_setup_done)

    function writefile(path::AbstractString, contents::AbstractString)
        mkpath(dirname(path))
        write(path, contents)
    end

    run_quiet(cmd) = run(pipeline(cmd; stdout=devnull, stderr=devnull))

    function ensure_examples!()
        rm("examples"; recursive=true, force=true)
        mkpath("examples")

        writefile("examples/DemoPackage.jl", """
        module DemoPackage

        include("helpers.jl")

        const DEFAULT_LIMIT = 10

        function foo(x)
            y = helper(x)
            z = y * 2
            return z
        end

        function increment(x)
            return x + 1
        end

        function old_function_name()
            return foo(1)
        end

        function obsolete()
            return :remove_me
        end

        end
        """)

        writefile("examples/helpers.jl", """
        helper(x) = x + 1
        """)

        writefile("examples/notes.txt", """
        First note.

        Second note.
        """)

        writefile("examples/error-example.jl", raw"""
        function inner(x)
            error("bad input: $x")
        end

        function outer(x)
            return inner(x + 1)
        end
        """)

        run_quiet(`git init -b main examples`)
        run_quiet(`git -C examples config user.email docs@example.com`)
        run_quiet(`git -C examples config user.name "CodeEdit Docs"`)
        run_quiet(`git -C examples add .`)
        run_quiet(`git -C examples commit -m "Initial shared examples"`)

        return nothing
    end
    _setup_done = true
    ensure_examples!()
end
