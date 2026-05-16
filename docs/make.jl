using Documenter
using CodeEdit

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
    doctestfilters = [
        r"/[0-9a-zA-Z/]*/examples",
        r"main [0-9a-f]*",
        r"commit [0-9a-f]*",
        ],
    #doctest = :fix,
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

clean_generated_html_paths(joinpath(@__DIR__, "build"), pwd())

rm(joinpath(@__DIR__, "examples"), recursive=true)
for f in ("scratch-note.txt", "scratch-safety.txt", "scratch.txt")
    rm(joinpath(@__DIR__, f))
end

if get(ENV, "CI", "false") == "true" && haskey(ENV, "GITHUB_REPOSITORY")
    deploydocs(
        repo = "github.com/$(ENV["GITHUB_REPOSITORY"]).git",
        push_preview = true,
    )
end
