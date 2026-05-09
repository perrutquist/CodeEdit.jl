# API reference

This page summarizes the public API exported by CodeEdit.jl.

## Handles

- [`Handle`](@ref): create a handle to the block containing a file location or method.
- [`eof_handle`](@ref): create a handle to the end of a file.
- [`handles`](@ref): collect handles for blocks in files.
- [`reindex`](@ref): update existing handles after files changed outside CodeEdit.jl.

## Searching

- [`search`](@ref): search handles, files, stacktraces, or exceptions.

## Edits

- [`AbstractEdit`](@ref): abstract supertype for edit values.
- [`Replace`](@ref): replace a block.
- [`Delete`](@ref): delete a block.
- [`InsertBefore`](@ref): insert code before a block.
- [`InsertAfter`](@ref): insert code after a block.
- [`CreateFile`](@ref): create a new file.
- [`MoveFile`](@ref): move or rename a file.
- [`DeleteFile`](@ref): delete a file.
- [`Combine`](@ref): combine edits into one planned edit.
- [`apply!`](@ref): apply a displayed edit.
- [`displayed!`](@ref): mark an edit as displayed.

## Convenience functions

- [`filepath`](@ref): return the file path for a handle.
- [`lines`](@ref): return the line range for a handle.
- [`docstring`](@ref): extract an attached docstring.
- [`is_valid`](@ref): test whether a handle or edit is valid.

## Exported names

```@autodocs
Modules = [CodeEdit]
Private = false
```
