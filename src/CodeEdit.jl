module CodeEdit

using JuliaSyntax, Glob
using SHA

const POST_APPLY_HOOKS = Pair{Symbol,Function}[]

function register_post_apply_hook!(name::Symbol, hook::Function)
    filter!(pair -> first(pair) != name, POST_APPLY_HOOKS)
    push!(POST_APPLY_HOOKS, name => hook)
    return hook
end

function run_post_apply_hooks!()
    for (name, hook) in copy(POST_APPLY_HOOKS)
        try
            hook()
        catch err
            @warn "post-apply hook failed" hook=name exception=(err, catch_backtrace())
        end
    end

    return nothing
end

include("types.jl")
include("spans.jl")
include("files.jl")
include("state.jl")
include("parse_text.jl")
include("parse_julia.jl")
include("parse.jl")
include("handles.jl")
include("display.jl")
include("search.jl")
include("edits.jl")
include("diff.jl")
include("plan.jl")
include("apply.jl")
include("reindex.jl")
include("methods.jl")

export Handle, eof_handle, handles, reindex
export search
export AbstractEdit, Replace, Delete, InsertBefore, InsertAfter
export CreateFile, MoveFile, DeleteFile, Combine, apply!, displayed!
export filepath, lines, docstring, is_valid

end
