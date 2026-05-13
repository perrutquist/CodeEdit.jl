const VALID_PARSE_MODES = (:auto, :julia, :text)

"""
Return an absolute normalized string path.
"""
absolute_path(path::AbstractString) = abspath(String(path))

"""
Return a canonical path suitable for comparing filesystem locations.

For paths that do not exist yet, canonicalize the nearest existing parent and
append the remaining path components. This keeps CreateFile paths comparable to
their git worktree root.
"""
function canonical_path(path::AbstractString)
    abs_path = absolute_path(path)

    if ispath(abs_path)
        return realpath(abs_path)
    end

    parts = String[]
    current = abs_path

    while !ispath(current)
        parent = dirname(current)
        parent == current && break
        pushfirst!(parts, basename(current))
        current = parent
    end

    base = ispath(current) ? realpath(current) : absolute_path(current)
    return normpath(joinpath(base, parts...))
end

"""
Return a canonical path normalized for case-insensitive filesystem comparison.
"""
function comparable_path(path::AbstractString)
    path = canonical_path(path)
    return Sys.iswindows() ? lowercase(path) : path
end

"""
Infer or validate a parse mode for `path`.
"""
function parse_mode_for_path(path::AbstractString; parse_as::Symbol=:auto)
    parse_as in VALID_PARSE_MODES || throw(ArgumentError("parse_as must be :auto, :julia, or :text"))

    parse_as == :auto || return parse_as
    return splitext(String(path))[2] == ".jl" ? :julia : :text
end

"""
Validate UTF-8 bytes and convert them to a String.
"""
function validate_utf8(bytes::Vector{UInt8}, path::AbstractString="<memory>")
    text = String(bytes)
    isvalid(text) || throw(ArgumentError("file contains invalid UTF-8: $path"))
    return text
end

"""
Compute a file stamp from existing file bytes and stat information.
"""
function file_stamp(path::AbstractString, bytes::Vector{UInt8}=read(path))
    st = stat(path)

    return FileStamp(
        Float64(st.mtime),
        Int64(st.size),
        sha1(bytes),
    )
end

"""
Return whether two file stamps describe identical file contents.
"""
function same_file_contents(a::FileStamp, b::FileStamp)
    return a.size == b.size && a.hash == b.hash
end

"""
Return the current filesystem identity for `path`.
"""
function file_id(path::AbstractString)
    st = stat(path)
    return FileID(UInt64(st.device), UInt64(st.inode))
end

"""
Detect the dominant line ending in `text`.
"""
function detect_line_ending(text::AbstractString)
    lf_count = 0
    crlf_count = 0

    for i in eachindex(text)
        if text[i] == '\n'
            lf_count += 1
            if i > firstindex(text) && text[prevind(text, i)] == '\r'
                crlf_count += 1
            end
        end
    end

    lf_only_count = lf_count - crlf_count
    return crlf_count > lf_only_count ? "\r\n" : "\n"
end

"""
Read a source file, validate UTF-8, and build basic file metadata.
"""
function read_source_file(path::AbstractString)
    path_string = String(path)
    bytes = read(path_string)
    text = validate_utf8(bytes, path_string)

    return (
        text = text,
        line_starts = build_line_starts(text),
        line_ending = detect_line_ending(text),
        stamp = file_stamp(path_string, bytes),
        id = file_id(path_string),
    )
end

"""
Return whether the path itself is a symlink.
"""
is_symlink_path(path::AbstractString) = islink(String(path))

"""
Reject symlink paths for mutating operations.
"""
function reject_symlink_path(path::AbstractString, operation::AbstractString)
    is_symlink_path(path) && error("cannot $operation through symlink path: $path")
    return nothing
end
