using Documenter
using CodeEdit

DocMeta.setdocmeta!(CodeEdit, :DocTestSetup, :(using CodeEdit); recursive=true)

const basedir = mktempdir()

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

makedocs(
    sitename = "CodeEdit.jl",
    modules = [CodeEdit],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
    ),
    pages = [
        "Manual" => [
            "Introduction" => "index.md",
            "A first edit" => "first-edit.md",
            "Finding code" => "finding-code.md",
            "Editing workflows" => "editing-workflow.md",
            "Debugging" => "debugging.md",
            "Safety" => "safety.md",
        ],
        "Library" => [
            "API reference" => "reference.md",
        ],
    ],
    checkdocs = :none,
    workdir = basedir,
)

clean_generated_html_paths(joinpath(@__DIR__, "build"), basedir)

if get(ENV, "CI", "false") == "true" && haskey(ENV, "GITHUB_REPOSITORY")
    deploydocs(
        repo = "github.com/$(ENV["GITHUB_REPOSITORY"]).git",
        push_preview = true,
    )
end
