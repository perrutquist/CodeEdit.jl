"""
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
Search all blocks in a file.
"""
function search(path::AbstractString, needle::AbstractString; parse_as::Symbol=:auto)
    return search(handles(path; parse_as=parse_as), needle)
end

"""
Search all blocks in a collection of files.
"""
function search(paths::AbstractVector{<:AbstractString}, needle::AbstractString; parse_as::Symbol=:auto)
    return search(handles(paths; parse_as=parse_as), needle)
end

"""
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
