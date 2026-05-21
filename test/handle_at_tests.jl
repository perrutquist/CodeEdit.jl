@testset "handle_at" begin
    mktempdir() do dir
        examples = mkpath(joinpath(dir, "examples"))
        demo = joinpath(examples, "DemoPackage.jl")

        write(
            demo,
            join(
                [
                    "module DemoPackage",
                    "",
                    "function foo(x)",
                    "    y = x + 1",
                    "    return y",
                    "end",
                    "",
                    "bar() = foo(1)",
                    "",
                    "end",
                ],
                "\n",
            ) * "\n",
        )

        hs = handles(demo)
        h = handle_at(hs, "DemoPackage.jl:4")

        @test hs["DemoPackage.jl:4"] === h
        @test handle_at(hs, "DemoPackage.jl", 4) === h
        @test handle_at(hs, "DemoPackage.jl:4:5") === h
        @test string(h) == "function foo(x)\n    y = x + 1\n    return y\nend\n"

        @test_throws ArgumentError handle_at(hs, "Missing.jl:1")
        @test_throws ArgumentError handle_at(hs, "DemoPackage.jl:not-a-line")
        @test_throws ArgumentError handle_at(hs, "DemoPackage.jl:100")
        @test_throws ArgumentError handle_at(hs, "DemoPackage.jl", 4, 100)

        other_dir = mkpath(joinpath(dir, "other"))
        other_demo = joinpath(other_dir, "DemoPackage.jl")
        write(other_demo, "other() = 1\n")

        both = handles([demo, other_demo])
        @test_throws ArgumentError handle_at(both, "DemoPackage.jl:1")
    end
end
