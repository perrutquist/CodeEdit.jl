"""
    AbstractEdit

Abstract supertype for all edit values.

Edit objects describe source or filesystem changes that can be displayed,
validated, and then applied with [`apply!`](@ref).
"""
abstract type AbstractEdit end

"""
Placeholder for the displayed-plan fingerprint used by later apply planning.
"""
struct DisplayedPlan
    fingerprint::String
    valid::Bool
    text::String
end

"""
    Replace(handle::Handle, code::AbstractString)

Edit that replaces the source block referred to by `handle` with `code`.
"""
struct Replace <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    Delete(handle::Handle)

Edit that deletes the source block referred to by `handle`.

Deleting an EOF handle has no effect.
"""
struct Delete <: AbstractEdit
    handle::Handle
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    InsertBefore(handle::Handle, code::AbstractString)

Edit that inserts `code` immediately before the source block referred to by
`handle`.
"""
struct InsertBefore <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    InsertAfter(handle::Handle, code::AbstractString)

Edit that inserts `code` immediately after the source block referred to by
`handle`.
"""
struct InsertAfter <: AbstractEdit
    handle::Handle
    code::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    CreateFile(path::AbstractString, code::AbstractString; parse_as::Symbol=:auto)

Edit that creates a new file at `path` containing `code`.

`parse_as` may be `:auto`, `:julia`, or `:text`.
"""
struct CreateFile <: AbstractEdit
    path::String
    code::String
    parse_as::Symbol
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    MoveFile(old_path::AbstractString, new_path::AbstractString)

Edit that moves or renames a file from `old_path` to `new_path`.
"""
struct MoveFile <: AbstractEdit
    old_path::String
    new_path::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    DeleteFile(path::AbstractString)

Edit that deletes the file at `path`.
"""
struct DeleteFile <: AbstractEdit
    path::String
    displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
end

"""
    Combine(edits::AbstractEdit...)
    Combine(edits::AbstractVector{<:AbstractEdit})

Edit that combines multiple edits into one planned operation.

Combined edits are interpreted in order and validated as a unit. Applying a
combined edit that touches multiple files is best-effort at the filesystem
level, so a later filesystem failure can leave earlier operations applied.
"""
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

