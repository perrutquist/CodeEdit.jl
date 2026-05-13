using Documenter
using CodeEdit

DocMeta.setdocmeta!(CodeEdit, :DocTestSetup, :(using CodeEdit); recursive=true)

basedir = mktempdir()

# In the examples, let the display_path be relative to the workdir
# (This is needed because display is rendered from the wrong directory during docs build.
function CodeEdit.display_path(path::AbstractString) 
    relpath(realpath(path), realpath(basedir))
end

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
        "Finding errors from stacktraces" => "searching-errors.md",
        "API reference" => "api.md",
    ],
    checkdocs = :none,
    workdir = basedir
)

if get(ENV, "CI", "false") == "true" && haskey(ENV, "GITHUB_REPOSITORY")
    deploydocs(
        repo = "github.com/$(ENV["GITHUB_REPOSITORY"]).git",
        push_preview = true,
    )
end
