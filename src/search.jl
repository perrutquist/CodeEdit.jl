"""
Return normalized stack frames for a Julia stacktrace-like object.
"""
function normalized_trace_frames(trace)
    try
        return stacktrace(trace)
    catch
        return trace
    end
end

"""
Return source locations from a Julia stacktrace-like object.
"""
function trace_locations(trace)
    locations = Tuple{String,Int}[]

    for frame in normalized_trace_frames(trace)
        hasproperty(frame, :file) || continue
        hasproperty(frame, :line) || continue

        file = getproperty(frame, :file)
        line = getproperty(frame, :line)

        if file !== nothing && line !== nothing
            try
                push!(locations, (absolute_path(String(file)), Int(line)))
            catch
            end
        end
    end

    return locations
end

"""
Return whether a handle contains any source location from a trace.
"""
function Base.occursin(handle::Handle, trace)
    is_valid(handle) || return false
    record = valid_handle_record(handle)
    handle_path = absolute_path(record.path)

    for (path, line) in trace_locations(trace)
        path == handle_path && line in record.lines && return true
    end

    return false
end

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
Search an existing handle collection for blocks referenced by a stacktrace.
"""
function search(handle_set, trace)
    result = Set{Handle}()

    for handle in handle_set
        occursin(handle, trace) && push!(result, handle)
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
