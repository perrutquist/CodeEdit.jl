"""
    search(handle_set, needle::AbstractString)

Search an existing handle collection for blocks containing `needle`.
"""
function search(handle_set, needle::AbstractString)
    result = Set{Handle}()

    for handle in handle_set
        is_valid(handle) || continue
        occursin(needle, string(handle)) && push!(result, handle)
    end

    return result
end

"""
    search(handle_set, needle::Regex)

Search an existing handle collection for blocks matching `needle`.
"""
function search(handle_set, needle::Regex)
    result = Set{Handle}()

    for handle in handle_set
        is_valid(handle) || continue
        occursin(needle, string(handle)) && push!(result, handle)
    end

    return result
end

"""
    search(path::AbstractString, needle::AbstractString; parse_as=:auto)

Search all blocks in a file.
"""
function search(path::AbstractString, needle::AbstractString; parse_as::Symbol=:auto)
    return search(handles(path; parse_as=parse_as), needle)
end

"""
    search(path::AbstractString, needle::Regex; parse_as=:auto)

Search all blocks in a file.
"""
function search(path::AbstractString, needle::Regex; parse_as::Symbol=:auto)
    return search(handles(path; parse_as=parse_as), needle)
end

"""
    search(paths::AbstractVector{<:AbstractString}, needle::AbstractString; parse_as=:auto)

Search all blocks in a collection of files.
"""
function search(paths::AbstractVector{<:AbstractString}, needle::AbstractString; parse_as::Symbol=:auto)
    return search(handles(paths; parse_as=parse_as), needle)
end

"""
    search(paths::AbstractVector{<:AbstractString}, needle::Regex; parse_as=:auto)

Search all blocks in a collection of files.
"""
function search(paths::AbstractVector{<:AbstractString}, needle::Regex; parse_as::Symbol=:auto)
    return search(handles(paths; parse_as=parse_as), needle)
end

"""
    search(root::AbstractString, pattern::AbstractString, needle::AbstractString; includes=false, parse_as=:auto)

Search files under `root` matching `pattern`.
"""
function search(
    root::AbstractString,
    pattern::AbstractString,
    needle::AbstractString;
    includes::Bool=false,
    parse_as::Symbol=:auto,
)
    return search(handles(root, pattern; includes=includes, parse_as=parse_as), needle)
end

"""
    search(root::AbstractString, pattern::AbstractString, needle::Regex; includes=false, parse_as=:auto)

Search files under `root` matching `pattern`.
"""
function search(
    root::AbstractString,
    pattern::AbstractString,
    needle::Regex;
    includes::Bool=false,
    parse_as::Symbol=:auto,
)
    return search(handles(root, pattern; includes=includes, parse_as=parse_as), needle)
end

"""
    search(repo::VersionControl, needle::AbstractString)

Search all handles returned by `handles(repo)`.
"""
function search(repo::VersionControl, needle::AbstractString)
    return search(handles(repo), needle)
end

"""
    search(repo::VersionControl, needle::Regex)

Search all handles returned by `handles(repo)`.
"""
function search(repo::VersionControl, needle::Regex)
    return search(handles(repo), needle)
end

"""
    search(repo::VersionControl, trace)

Search all handles returned by `handles(repo)` for blocks referenced by a
stacktrace or backtrace-like object.
"""
function search(repo::VersionControl, trace)
    return search(handles(repo), trace)
end
