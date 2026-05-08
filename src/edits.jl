abstract type AbstractEdit end

"""
Placeholder for the displayed-plan fingerprint used by later apply planning.
"""
struct DisplayedPlan
    fingerprint::String
    valid::Bool
    text::String
end

struct Replace <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

struct Delete <: AbstractEdit
    handle::Handle
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

struct InsertBefore <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

struct InsertAfter <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

struct CreateFile <: AbstractEdit
    path::String
    code::String
    parse_as::Symbol
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

struct MoveFile <: AbstractEdit
    old_path::String
    new_path::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

struct DeleteFile <: AbstractEdit
    path::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

struct Combine <: AbstractEdit
    edits::Vector{AbstractEdit}
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

display_ref() = Ref{Union{Nothing,DisplayedPlan}}(nothing)

Replace(handle::Handle, code::AbstractString) = Replace(handle, String(code), display_ref())
Delete(handle::Handle) = Delete(handle, display_ref())
InsertBefore(handle::Handle, code::AbstractString) = InsertBefore(handle, String(code), display_ref())
InsertAfter(handle::Handle, code::AbstractString) = InsertAfter(handle, String(code), display_ref())

function CreateFile(path::AbstractString, code::AbstractString; parse_as::Symbol=:auto)
    parse_as in VALID_PARSE_MODES || throw(ArgumentError("parse_as must be :auto, :julia, or :text"))
    return CreateFile(String(path), String(code), parse_as, display_ref())
end

MoveFile(old_path::AbstractString, new_path::AbstractString) =
    MoveFile(String(old_path), String(new_path), display_ref())

DeleteFile(path::AbstractString) = DeleteFile(String(path), display_ref())

Combine(edits::AbstractEdit...) = Combine(AbstractEdit[edits...], display_ref())
Combine(edits::AbstractVector{<:AbstractEdit}) = Combine(AbstractEdit[edits...], display_ref())

Base.:*(a::AbstractEdit, b::AbstractEdit) = Combine(a, b)

"""
Set or clear the displayed marker for an edit.

Full plan compilation is implemented later; for now this records a stable
placeholder marker so constructors and state transitions are testable.
"""
function displayed!(edit::AbstractEdit, displayed::Bool=true)
    edit.displayed[] = displayed ? DisplayedPlan("", true, "") : nothing
    return edit
end

"""
Return whether the current edit object is structurally valid.

Syntax/filesystem validation is added with edit planning.
"""
is_valid(edit::AbstractEdit) = true

function Base.show(io::IO, ::MIME"text/plain", edit::AbstractEdit)
    print(io, summary(edit))
end

function Base.show(io::IO, edit::AbstractEdit)
    print(io, summary(edit))
end
