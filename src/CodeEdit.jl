module CodeEdit

using JuliaSyntax, Glob, SHA

const _maybe_revise_callback = Ref{Function}(() -> nothing)

function maybe_revise()
    _maybe_revise_callback[]()
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
