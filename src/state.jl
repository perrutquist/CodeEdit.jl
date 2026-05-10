"""
Global mutable package state.
"""
mutable struct CacheState
    files::Dict{FileKey,FileCache}
    path_index::Dict{String,FileKey}
    id_index::Dict{FileID,FileKey}
    handles::Dict{Int,HandleRecord}
    next_file_key::Int
    next_handle::Int
end

CacheState() = CacheState(
    Dict{FileKey,FileCache}(),
    Dict{String,FileKey}(),
    Dict{FileID,FileKey}(),
    Dict{Int,HandleRecord}(),
    1,
    1,
)

const STATE = Ref(CacheState())

"""
Clear all cached files and handles. Intended for tests.
"""
function clear_cache!()
    STATE[] = CacheState()
    return nothing
end

"""
Allocate a new logical file key.
"""
function allocate_file_key!()
    state = STATE[]
    key = FileKey(state.next_file_key)
    state.next_file_key += 1
    return key
end

"""
Allocate a new internal handle id.
"""
function allocate_handle_id!()
    state = STATE[]
    id = state.next_handle
    state.next_handle += 1
    return id
end

"""
Store a handle record and return its public handle.
"""
function register_handle!(record::HandleRecord)
    id = allocate_handle_id!()
    STATE[].handles[id] = record
    return Handle(id)
end

"""
Return the registry record for a valid public handle id.
"""
function handle_record(handle::Handle)
    return get(STATE[].handles, handle.id, nothing)
end

"""
Invalidate all registered handles for a logical file.
"""
function invalidate_file_handles!(key::FileKey)
    for record in values(STATE[].handles)
        if record.file == key
            record.valid = false
            record.file = nothing
        end
    end

    return nothing
end

"""
Remove a cached file and its path/identity indexes.

Existing handles for the file are invalidated by default. This is used when a
cached filesystem object disappears or is replaced, so future lookups of the
same path build a fresh cache instead of reusing stale handle ids.
"""
function remove_file_cache!(key::FileKey; invalidate_handles::Bool=true)
    state = STATE[]
    haskey(state.files, key) || return nothing

    cache = state.files[key]
    invalidate_handles && invalidate_file_handles!(key)

    for path in cache.paths
        get(state.path_index, path, nothing) == key && delete!(state.path_index, path)
    end

    get(state.path_index, cache.primary_path, nothing) == key && delete!(state.path_index, cache.primary_path)

    if cache.current_id !== nothing && get(state.id_index, cache.current_id, nothing) == key
        delete!(state.id_index, cache.current_id)
    end

    delete!(state.files, key)
    return nothing
end
