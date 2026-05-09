using Documenter
using CodeEdit

DocMeta.setdocmeta!(CodeEdit, :DocTestSetup, :(using CodeEdit); recursive=true)

examples_dir = abspath("examples")
rm(examples_dir; recursive=true, force=true)

try
    makedocs(
        sitename = "CodeEdit.jl",
        modules = [CodeEdit],
        format = Documenter.HTML(
            prettyurls = get(ENV, "CI", "false") == "true",
        ),
        pages = [
            "Home" => "index.md",
            "Getting started" => "getting-started.md",
            "Editing code" => "editing.md",
            "Finding errors from stacktraces" => "searching-errors.md",
            "API reference" => "api.md",
        ],
        checkdocs = :none,
        workdir = @__DIR__
    )

    if get(ENV, "CI", "false") == "true" && haskey(ENV, "GITHUB_REPOSITORY")
        deploydocs(
            repo = "github.com/$(ENV["GITHUB_REPOSITORY"]).git",
            push_preview = true,
        )
    end
finally
    rm(examples_dir; recursive=true, force=true)
end
