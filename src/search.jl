"""
    find(target, query; files=nothing, as=:auto)
    find(predicate, target; files=nothing, as=:auto)
    search(args...; kwargs...)
    grep(args...; kwargs...)

Search parsed blocks and return matching blocks.

`query` may be a string or `Regex`. Predicate forms keep ordinary Julia
filtering ergonomics, including `find(target) do block ... end`. Set-like
inputs return a `Set{Block}`; vector inputs preserve order and return a vector.
"""
function _query_predicate(needle::AbstractString)
    return handle -> is_valid(handle) && occursin(needle, source(handle))
end

function _query_predicate(needle::Regex)
    return handle -> is_valid(handle) && occursin(needle, source(handle))
end

function _filter_block_collection(collection::AbstractVector{Block}, predicate::Function)
    return Block[handle for handle in collection if predicate(handle)]
end

function _filter_block_collection(collection, predicate::Function)
    result = Set{Block}()

    for handle in collection
        predicate(handle) && push!(result, handle)
    end

    return result
end

function _blocks_for_search(
    target;
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    return target
end

function _blocks_for_search(
    ws::Workspace;
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    return blocks(ws; files=files, as=as, parse_as=parse_as, includes=includes, follow_includes=follow_includes)
end

function _blocks_for_search(
    path::AbstractString;
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    return blocks(path; files=files, as=as, parse_as=parse_as, includes=includes, follow_includes=follow_includes)
end

function _blocks_for_search(
    paths::AbstractVector{<:AbstractString};
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    files === nothing || throw(ArgumentError("files= is only supported when searching a workspace or root path"))
    return blocks(paths; as=as, parse_as=parse_as, includes=includes, follow_includes=follow_includes)
end

function _blocks_for_search(
    vc::VersionControl;
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    files === nothing || throw(ArgumentError("files= is not supported when searching VersionControl directly"))
    mode = _normalize_parse_as(as=as, parse_as=parse_as)
    return handles(vc; includes=follow_includes, parse_as=mode)
end

function find(
    predicate::Function,
    target;
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    collection = _blocks_for_search(
        target;
        files=files,
        as=as,
        parse_as=parse_as,
        includes=includes,
        follow_includes=follow_includes,
    )
    return _filter_block_collection(collection, predicate)
end

function find(
    target,
    needle;
    files=nothing,
    as::Symbol=:auto,
    parse_as=nothing,
    includes::Bool=false,
    follow_includes::Bool=includes,
)
    return find(
        _query_predicate(needle),
        target;
        files=files,
        as=as,
        parse_as=parse_as,
        includes=includes,
        follow_includes=follow_includes,
    )
end

search(args...; kwargs...) = find(args...; kwargs...)
grep(args...; kwargs...) = find(args...; kwargs...)
