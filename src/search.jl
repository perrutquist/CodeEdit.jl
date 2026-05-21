"""
    search(handles, needle)
    search(path, needle; parse_as=:auto)
    search(paths, needle; parse_as=:auto)
    search(root, pattern, needle; includes=false, parse_as=:auto)
    search(repo::VersionControl, needle)

Search parsed blocks and return matching handles as a `Set{Handle}`.

`needle` may be a string, matched with `occursin`, or a `Regex`. Path arguments
are first converted to handles with [`handles`](@ref). The `(root, pattern)`
form uses `Glob.glob`; the repository form searches handles returned by
`handles(repo)`.
"""
function search(handle_set, needle::AbstractString)
    result = Set{Handle}()

    for handle in handle_set
        is_valid(handle) || continue
        occursin(needle, string(handle)) && push!(result, handle)
    end

    return result
end

function search(handle_set, needle::Regex)
    result = Set{Handle}()

    for handle in handle_set
        is_valid(handle) || continue
        occursin(needle, string(handle)) && push!(result, handle)
    end

    return result
end

function search(path::AbstractString, needle::AbstractString; parse_as::Symbol=:auto)
    return search(handles(path; parse_as=parse_as), needle)
end

function search(path::AbstractString, needle::Regex; parse_as::Symbol=:auto)
    return search(handles(path; parse_as=parse_as), needle)
end

function search(paths::AbstractVector{<:AbstractString}, needle::AbstractString; parse_as::Symbol=:auto)
    return search(handles(paths; parse_as=parse_as), needle)
end

function search(paths::AbstractVector{<:AbstractString}, needle::Regex; parse_as::Symbol=:auto)
    return search(handles(paths; parse_as=parse_as), needle)
end

function search(
    root::AbstractString,
    pattern::AbstractString,
    needle::AbstractString;
    includes::Bool=false,
    parse_as::Symbol=:auto,
)
    return search(handles(root, pattern; includes=includes, parse_as=parse_as), needle)
end

function search(
    root::AbstractString,
    pattern::AbstractString,
    needle::Regex;
    includes::Bool=false,
    parse_as::Symbol=:auto,
)
    return search(handles(root, pattern; includes=includes, parse_as=parse_as), needle)
end

function search(repo::VersionControl, needle::AbstractString)
    return search(handles(repo), needle)
end

function search(repo::VersionControl, needle::Regex)
    return search(handles(repo), needle)
end

function search(repo::VersionControl, trace)
    return search(handles(repo), trace)
end
