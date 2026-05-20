
display_ref() = Ref{Union{Nothing,DisplayedPlan}}(nothing)

Replace(handle::Handle, code::AbstractString) = Replace(handle, String(code), display_ref())
Delete(handle::Handle) = Delete(handle, display_ref())
InsertBefore(handle::Handle, code::AbstractString) = InsertBefore(handle, String(code), display_ref())
InsertAfter(handle::Handle, code::AbstractString) = InsertAfter(handle, String(code), display_ref())

function CreateFile(path::AbstractString, code::AbstractString; parse_as::Symbol=:auto)
    parse_as in VALID_PARSE_MODES || throw(ArgumentError("parse_as must be :auto, :julia, or :text"))
    return CreateFile(absolute_path(path), String(code), parse_as, display_ref())
end

MoveFile(old_path::AbstractString, new_path::AbstractString) =
    MoveFile(absolute_path(old_path), absolute_path(new_path), display_ref())

DeleteFile(path::AbstractString) = DeleteFile(absolute_path(path), display_ref())

Combine(edits::AbstractEdit...) = Combine(AbstractEdit[edits...], display_ref())
Combine(edits::AbstractVector{<:AbstractEdit}) = Combine(AbstractEdit[edits...], display_ref())

"""
    edit1 * edit2

Shorthand for `Combine(edit1, edit2)`. Chaining `*` appends edits to a combined
edit in left-to-right order.
"""
Base.:*(a::AbstractEdit, b::AbstractEdit) = Combine(a, b)
Base.:*(a::Combine, b::AbstractEdit) = Combine(vcat(a.edits, AbstractEdit[b]), display_ref())
Base.:*(a::AbstractEdit, b::Combine) = Combine(vcat(AbstractEdit[a], b.edits), display_ref())

