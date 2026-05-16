using Documenter
using CodeEdit

include("setup.jl")

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
    doctestfilters = [
        r"/[0-9a-zA-Z/]*/examples",
        r"main [0-9a-f]*",
        r"commit [0-9a-f]*",
        ],
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
