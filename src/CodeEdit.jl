module CodeEdit

using JuliaSyntax, Glob
using SHA

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

export Handle, eof_handle, handles
export search
export AbstractEdit, Replace, Delete, InsertBefore, InsertAfter
export CreateFile, MoveFile, DeleteFile, Combine, apply!, displayed!
export filepath, lines, docstring, is_valid

end
