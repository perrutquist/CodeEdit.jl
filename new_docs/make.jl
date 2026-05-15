using Documenter
using CodeEdit

DocMeta.setdocmeta!(CodeEdit, :DocTestSetup, :(using CodeEdit); recursive=true)

const basedir = mktempdir()

makedocs(
    sitename = "CodeEdit.jl",
    modules = [CodeEdit],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
    ),
    pages = [
        "Home" => "index.md",
        "A first careful edit" => "first-edit.md",
        "Finding your way around" => "finding-code.md",
        "Changing more than one thing" => "editing-workflow.md",
        "Following an error home" => "debugging.md",
        "Working safely" => "safety.md",
        "API reference" => "reference.md",
    ],
    checkdocs = :none,
    workdir = basedir,
)

if get(ENV, "CI", "false") == "true" && haskey(ENV, "GITHUB_REPOSITORY")
    deploydocs(
        repo = "github.com/$(ENV["GITHUB_REPOSITORY"]).git",
        push_preview = true,
    )
end
