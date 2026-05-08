# CodeEdit.jl implementation structure

This document describes a small, conservative, testable implementation of the `CodeEdit.jl` API.

The design favors:

- correctness over cleverness,
- explicit internal state,
- conservative failure on ambiguity,
- literal source preservation where possible,
- clear separation between parsing, handle management, edit planning, display, validation, applying edits, and reindexing.

---

## 1. Design goals

### Goals

- Support only the latest stable Julia release.
- Use `JuliaSyntax.jl` for Julia parsing.
- Preserve source text literally where practical:
  - line endings,
  - trailing final newline state,
  - comments,
  - whitespace,
  - indentation.
- Divide files into non-overlapping blocks.
- Keep handles stable across safe edits and reindexing.
- Reject ambiguous or unsafe edits.
- Validate modified Julia files by reparsing the whole modified file before writing.
- Require edits to be displayed before applying.
- Keep public APIs small and implementation details testable.

### Non-goals

- Full transactional filesystem semantics across multiple files.
- Undo support.
- Macro expansion.
- Semantic validation.
- Deep editor integration.
- Explicit Revise.jl integration.
- Concurrent mutation or thread safety.
- Perfect support for exotic Julia syntax.

---

## 2. Proposed source tree

```text
CodeEdit.jl/
├── Project.toml
├── src/
│   ├── CodeEdit.jl          # module, exports, includes
│   ├── types.jl             # core structs used across files
│   ├── spans.jl             # byte spans, line index helpers
│   ├── files.jl             # file identity, stamps, reading/writing
│   ├── state.jl             # global cache, registries, test reset
│   ├── blocks.jl            # block utilities
│   ├── parse.jl             # generic parse dispatch
│   ├── parse_julia.jl       # JuliaSyntax-based block detection
│   ├── parse_text.jl        # paragraph/blank-line text blocks
│   ├── handles.jl           # public handle constructors/utilities
│   ├── reindex.jl           # handle preservation after file changes
│   ├── edits.jl             # public edit constructors/operators
│   ├── plan.jl              # edit compilation, conflict checks
│   ├── validate.jl          # syntax/UTF-8 validation
│   ├── diff.jl              # stable classic line diff
│   ├── display.jl           # show methods for handles/edits/sets
│   ├── apply.jl             # apply!, atomic writes, cache updates
│   ├── search.jl            # string, stacktrace, exception search
│   └── methods.jl           # Method/source-location integration
└── test/
    ├── runtests.jl
    ├── parsing.jl
    ├── handles.jl
    ├── edits.jl
    ├── apply.jl
    ├── reindex.jl
    ├── display.jl
    ├── search.jl
    ├── filesystem.jl
    └── fixtures/
```

`src/CodeEdit.jl` should be thin:

```julia
module CodeEdit

using JuliaSyntax
using SHA

include("types.jl")
include("spans.jl")
include("files.jl")
include("state.jl")
include("blocks.jl")
include("parse.jl")
include("parse_julia.jl")
include("parse_text.jl")
include("handles.jl")
include("reindex.jl")
include("edits.jl")
include("plan.jl")
include("validate.jl")
include("diff.jl")
include("display.jl")
include("apply.jl")
include("search.jl")
include("methods.jl")

export Handle, eof_handle, handles, reindex
export search
export Replace, Delete, InsertBefore, InsertAfter
export CreateFile, MoveFile, DeleteFile, Combine, apply!, displayed!
export filepath, lines, docstring, is_valid

end
```

---

## 3. Core internal model

### 3.1 File identity

Filesystem inode/device identity is useful but cannot be the sole cache key, because atomic replacement usually creates a new inode.

Use two concepts:

1. **Filesystem identity**: current `stat(path)` device/inode.
2. **Logical file key**: stable internal identity for a cached file across atomic replacement.

```julia
"""
Current identity of an existing filesystem object.
"""
struct FileID
    device::UInt64
    inode::UInt64
end

"""
Stable internal identity for a cached logical file.
Survives atomic replacement when CodeEdit writes the file.
"""
struct FileKey
    id::Int
end
```

Use `FileID` to coalesce paths that currently refer to the same file. Use `FileKey` as the primary key for cached files and handle records.

### 3.2 File stamps

Use file stamps to detect external changes and to enforce displayed-edit safety.

```julia
"""
Change detector for file contents.
"""
struct FileStamp
    mtime::Float64
    size::Int64
    hash::Vector{UInt8}
end
```

The hash makes safety stronger than mtime alone.

For non-existing paths involved in file operations, use explicit path preconditions rather than `FileStamp`.

```julia
abstract type PathCondition end

struct MustExist <: PathCondition
    path::String
    stamp::FileStamp
end

struct MustNotExist <: PathCondition
    path::String
end
```

---

## 4. Spans and line positions

### 4.1 Byte spans

Use half-open byte spans into a `String`.

```julia
"""
Half-open byte interval `[lo, hi)`.
"""
struct Span
    lo::Int
    hi::Int
end
```

Invariants:

- `1 <= lo <= hi <= ncodeunits(text) + 1`
- `lo == hi` is an insertion point.
- EOF is `Span(ncodeunits(text) + 1, ncodeunits(text) + 1)`.

All slicing should go through helpers in `spans.jl`.

### 4.2 Block span convention

A block span covers whole source/text lines, including their terminating line endings where present.

Example:

```julia
function f()
    1
end
```

The block span includes the newline after `end` if it exists.

This makes:

- `Delete(handle)` remove the whole block cleanly,
- `InsertAfter(handle, code)` insert after the block’s final newline,
- source preservation predictable.

EOF is a zero-width block at the end of the file.

EOF line convention:

```text
EOF line = number of lines in the file + 1
```

For an empty file, EOF is line `1`.

### 4.3 Character positions

The public API uses:

```julia
Handle(path, line, pos=1)
```

where `pos` is a character/codepoint position within the line, not a byte offset.

Conversion must use Julia string indexing utilities such as `nextind`. Never compute byte offsets as:

```julia
line_start + pos - 1
```

because that is wrong for Unicode.

---

## 5. Blocks

```julia
"""
A parsed block of source or text.
"""
struct Block
    span::Span
    lines::UnitRange{Int}
    kind::Symbol
    docspan::Union{Nothing,Span}
end
```

Suggested internal `kind` values:

- `:julia`
- `:text`
- `:module_header`
- `:module_footer`
- `:eof`

`kind` should remain internal unless there is a clear public need.

Blocks must never overlap.

---

## 6. Cached files

```julia
"""
Parsed representation of a logical cached file.
"""
mutable struct FileCache
    key::FileKey
    current_id::Union{Nothing,FileID}
    primary_path::String
    paths::Set{String}
    stamp::FileStamp
    parse_as::Symbol
    text::String
    line_starts::Vector{Int}
    line_ending::String
    blocks::Vector{Block}
    handles::Vector{Int}
    generation::Int
end
```

Notes:

- `primary_path` is the path most recently used for writing/display.
- `paths` stores known aliases as supplied by users.
- `current_id` is refreshed from `stat(primary_path)`.
- Atomic writes may change `current_id`, but the `FileKey` remains stable.
- `blocks[i]` and `handles[i]` correspond.
- `handles[i]` is the internal handle id for that block.

---

## 7. Handles

### 7.1 Public handle type

```julia
"""
Reference to a source/text block.
"""
struct Handle
    id::Int
end
```

Handles referring to the same block should compare identical with `===`.

For immutable Julia values:

```julia
Handle(1) === Handle(1)
```

is true, so interning by integer id is sufficient.

### 7.2 Handle records

```julia
"""
Mutable registry entry backing a Handle.
"""
mutable struct HandleRecord
    file::Union{Nothing,FileKey}
    path::String              # path as supplied/associated with this handle
    block_index::Int
    span::Span
    lines::UnitRange{Int}
    text::String
    doc::Union{Nothing,String}
    valid::Bool
end
```

Properties:

- Public `Handle` values are immutable.
- Invalidation only mutates `HandleRecord`.
- Existing handles can adapt when their backing record is updated.
- Invalid handles never become valid again.
- `string(h)` should throw for invalid handles; it should not return stale text.

---

## 8. Global state

Keep global mutable state simple and internal.

```julia
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
```

Provide an internal test helper:

```julia
"""
Clear all cached files and handles. Intended for tests.
"""
clear_cache!()
```

Do not attempt thread safety initially. Document that concurrent mutation is unsupported.

---

## 9. File reading and writing

All file reads should:

1. read bytes,
2. validate UTF-8,
3. convert to `String`,
4. detect dominant line ending,
5. build line index,
6. compute `FileStamp`.

Dominant line ending:

- `"\n"` if LF dominates or no line ending exists,
- `"\r\n"` if CRLF dominates.

Mixed endings may not be perfectly preserved after edits, but parsing/display should not normalize existing text.

### Atomic content writes

For content edits to existing files:

1. Write new content to a temp file in the same directory.
2. Copy mode bits from the original file where possible.
3. Flush and close.
4. Rename the temp file over the target.
5. Refresh `current_id` and `stamp`.

### Symlink policy

Atomic rename over a symlink path may replace the symlink itself rather than the target. Initially use one conservative policy:

- either resolve to `realpath(path)` before writing,
- or reject writing through symlink paths with a clear error.

The recommended initial implementation is to **reject writing through symlink paths** unless tests explicitly cover realpath behavior.

---

## 10. Parsing pipeline

All file loading should go through one path:

```text
path
  ↓
resolve/load existing cache if safe
  ↓
read bytes/string
  ↓
validate UTF-8
  ↓
detect line endings
  ↓
build line index
  ↓
parse as Julia or text
  ↓
append EOF block
  ↓
intern/reuse handles
  ↓
store/update FileCache
```

Internal entry point:

```julia
"""
Load and parse a file, returning its cache entry.
"""
load_file(path::AbstractString; parse_as=:auto)
```

`parse_as=:auto` means:

- `.jl` → `:julia`
- otherwise → `:text`

Public APIs that load files should accept:

```julia
parse_as=:auto
```

Allowed values:

- `:auto`
- `:julia`
- `:text`

If the parse mode for an already cached logical file changes, invalidate old handles for that file and reload.

---

## 11. Julia parsing

Use `JuliaSyntax.jl`.

Responsibilities of `parse_julia.jl`:

1. Parse the whole file.
2. Throw `ArgumentError` on parse errors.
3. Identify top-level syntactic expressions.
4. Attach immediately adjacent leading comments to the following block.
5. Attach immediately adjacent docstrings to the following block.
6. Treat multiple stacked docstrings as part of one block.
7. Attach docstrings only to the immediately following definition/block.
8. Split modules specially:
   - module header line is one block,
   - module contents are subdivided normally,
   - matching `end` line is one block.
9. Leave EOF block creation to generic parse code.

Conservative rule:

> If the parser tree does not make a boundary clear, do not invent one. Either keep the larger syntactic expression as one block or throw `ArgumentError` if correctness is uncertain.

Top-level `begin`, `let`, `quote`, `if`, `for`, `while`, etc. should be one block each, except for special module splitting.

`include("file.jl")` is just a normal top-level block during parsing. Recursive include traversal is handled by `handles(...; includes=true)`.

### Docstring extraction

`docstring(handle)` should return text, not Julia source code.

Supported initially:

- ordinary string literal docstrings,
- triple-quoted docstrings,
- stacked docstrings.

Do not macro-expand or evaluate arbitrary code. If extracting doc text is uncertain, return a conservative best-effort result or `nothing`; do not execute source code.

Tests should cover:

```julia
"doc"
function f end
```

```julia
"""
doc 1
"""
"""
doc 2
"""
function f end
```

```julia
module M
"doc"
f(x) = x
end
```

---

## 12. Text parsing

For non-Julia files, split blocks by blank lines.

Rules:

- A block is a maximal run of nonblank lines.
- The block includes original line endings for those lines.
- Blank-line runs are not blocks.
- Querying a blank region returns the next block after that location.
- If there is no next block, return EOF.
- Always append EOF block.

---

## 13. Public handle APIs

Implement:

```julia
Handle(path, line, pos=1; parse_as=:auto)
Handle(method)
eof_handle(path; parse_as=:auto)
handles(path; parse_as=:auto)
handles(paths; parse_as=:auto)
handles(root, glob; includes=false, parse_as=:auto)
```

`handles(...)` returns a `Set{Handle}` including EOF handles.

### `handles(root, glob)`

Julia Base does not provide a full glob implementation - depend on `Glob.jl`.

### Recursive includes

For:

```julia
handles(path; includes=true)
```

and:

```julia
handles(root, glob; includes=true)
```

follow `include("...")` statements recursively when:

- the included path is a string literal,
- it can be resolved relative to the including file,
- the target exists.

Do not evaluate dynamic include expressions.

### Location lookup

For `Handle(path, line, pos)`:

1. Load/reindex file as needed.
2. Convert `(line, pos)` to byte offset.
3. Find block containing the offset.
4. If none, choose next block after the offset.
5. If none, return EOF handle.

### Invalid handles

- `is_valid(h) == false`
- `display(h)` prints `#invalid`
- `string(h)` throws
- `filepath(h)` and `lines(h)` throw

---

## 14. Edit types

Public edit objects should be declarative.

```julia
abstract type AbstractEdit end
```

Each edit stores a displayed marker:

```julia
displayed::Base.RefValue{Union{Nothing,DisplayedPlan}}
```

Define edit structs:

```julia
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
```

Provide outer constructors so users do not pass `displayed` manually.

Example:

```julia
Replace(h::Handle, code::AbstractString) =
    Replace(h, String(code), Ref{Union{Nothing,DisplayedPlan}}(nothing))
```

Also define:

```julia
Base.:*(a::AbstractEdit, b::AbstractEdit) = Combine(a, b)
```

`Combine` is an ordered edit. Its child edits are planned and applied conceptually from left to right, and each child edit sees the virtual filesystem state produced by the previous child edits. Intermediate states are tracked directly from the ordered edits and are not reparsed until the full combined edit has been interpreted.

`Combine(edit1, edit2, ...)` preserves the given order. Nested combines are flattened during planning, preserving left-to-right order. Thus `Combine(a, Combine(b, c))` and `a * b * c` are planned as `a`, then `b`, then `c`.

Displaying a `Combine` does not mark child edits as displayed. The displayed marker belongs to the exact combined plan, including the order of all child edits and all intermediate file states relevant to handle resolution.

---

## 15. Primitive edit operations

Use internal primitive operations during planning.

```julia
"""
Single byte-range replacement within one logical file.
"""
struct Replacement
    file::FileKey
    path::String
    span::Span
    code::String
    source_handle::Union{Nothing,Handle}
end

struct CreateOp
    path::String
    code::String
    parse_as::Symbol
end

struct MoveOp
    old_path::String
    new_path::String
end

struct DeleteOp
    path::String
end
```

---

## 16. Edit planning

Separate public edit objects from executable plans. A plan is compiled by interpreting edits against a virtual filesystem state, without mutating the real filesystem or the global handle registry.

During planning, each touched file has a virtual state containing its current path, text, parse mode, initial parsed blocks, line index, file stamp or path precondition, and temporary handle bindings. After each ordered edit step, those virtual handle bindings and block locations are updated directly from the edit operations rather than by reparsing intermediate file contents. Later edits in a `Combine` therefore resolve handles against the tracked virtual state produced by earlier edits, and reparsing is deferred until the full ordered sequence has been interpreted.

A handle-based edit is resolved at the moment that edit is reached in the ordered sequence. If an earlier edit shifted, replaced, moved, or invalidated the handle’s block, the later edit observes that updated tracked state. If the planner cannot determine the handle’s current block unambiguously, planning fails conservatively.

Planning pipeline:

1. Flatten `Combine` edits into an ordered sequence.
2. Initialize virtual file states from the current cache/filesystem state.
3. Interpret each edit in order.
4. Resolve handles against the current virtual state.
5. Check path preconditions against the current virtual path state.
6. Apply the edit to the virtual state.
7. Update tracked block locations and virtual handle bindings after each content edit or file move, without reparsing intermediate states.
8. Reject ambiguous, invalid, or unsafe tracked intermediate handle/path states.
9. Reparse and validate final modified and created file contents after the full ordered sequence has been interpreted.
10. Produce a final executable plan and diff.
11. Produce a final executable plan and diff.

`EditPlan` should retain both the final grouped effects and the ordered operation trace used to produce them. The ordered trace is needed for display hashing, debugging, and faithful application of file creates, moves, deletes, and content writes.

A modified file plan represents the final content of a logical file after all ordered edits have been interpreted. It should also record the original stamp/path condition and the ordered replacements that led to the final text.

A useful internal model is:

- `VirtualFileState`: current in-memory state of a touched logical file.
- `VirtualHandleState`: current planned binding of a handle id to a block, or invalid.
- `PlanStep`: one ordered primitive operation after handle/path resolution.
- `ModifiedFilePlan`: final old/new text pair for one surviving modified file.
- `EditPlan`: ordered steps plus final creates, moves, deletes, modified files, path conditions, diff, validation status, and errors.

### Combine semantics

Use ordered semantics for `Combine`.

All child edits are interpreted from left to right against a virtual copy of the involved files and paths. Earlier edits can affect the meaning of later edits. For example, if `InsertBefore(h, code)` inserts text before `h`, a later `Replace(h, other)` resolves `h` at its shifted location. Intermediate virtual file contents do not need to be syntactically valid, because reparsing is deferred until the full ordered sequence has completed.

Handles track their blocks through the virtual edit sequence when this is unambiguous. File moves update the virtual path associated with handles to that logical file. Deleting a block invalidates the corresponding virtual handle for the remainder of the plan. Replacements and insertions update tracked block locations directly from their ordered byte-span effects; the planner does not require intermediate reparses to keep later handle resolution working. Once the whole ordered sequence has been interpreted, the final file contents are reparsed, validated, and used to determine final handle preservation conservatively.

Planning must not mutate public handle records. The handle tracking described here is local to the plan. Public handles are updated only after `apply!` succeeds.

### Conflict policy

Conflicts are checked at each ordered step against the current virtual state, not only against the original snapshot.

Reject by default:

- use of an invalid handle at the point where it is resolved,
- overlapping replacements within the same single planning step,
- an edit whose target block cannot be found unambiguously after previous edits,
- a filesystem operation whose source/destination preconditions do not hold in the current virtual path state,
- deleting or moving a file and then later editing a handle whose logical file no longer exists,
- creating a file at a virtual path that already exists,
- moving a file to a virtual path that already exists,
- ambiguous handle tracking after replacement or other range-changing edits,
- any ordered combination whose final filesystem effects cannot be represented safely.

Allow when unambiguous:

- repeated edits to the same handle, if each previous edit preserved that handle,
- insertion before/after a handle followed by another edit to that same handle,
- moving a file followed by edits to handles from that file, with handles resolving at the new virtual path,
- editing a file and then moving it,
- moving a file and then deleting it,
- `Combine(InsertBefore(destination, string(source)), Delete(source))`, including when both handles are in the same file, provided the source handle still resolves unambiguously after the insertion.

Same-location insertions resolve in the order they appear in the flattened `Combine`. `Combine(InsertBefore(C, A), InsertBefore(C, B))` gives the order `A`, `B`, `C`.

### EOF behavior

EOF handles also track the virtual file state. After earlier insertions, moves, or replacements, a later EOF edit resolves to the current virtual end of the corresponding logical file.

`Delete(EOF)` is a no-op.

`Replace(EOF, code)` behaves like `InsertBefore(EOF, code)`.

`InsertAfter(EOF, code)` behaves like `InsertBefore(EOF, code)`.

### Insertions

Insertions do not add newlines automatically. Insert `code` exactly as supplied.

After an insertion, later ordered edits continue to resolve handles using the tracked virtual block locations produced by the ordered edits. If that tracking becomes ambiguous, planning fails. Reparsing is deferred until the final combined result is validated.

---

## 17. Validation

Validation is syntax/encoding only.

Intermediate states within an ordered `Combine` do not need to parse successfully. Validation is applied only to the final modified or created file contents.

For each modified or created file:

- If parsed as Julia:
  - validate UTF-8,
  - parse the whole modified file with `JuliaSyntax`,
  - reject parse errors.
- If parsed as text:
  - validate UTF-8 only.

Do not:

- run macro expansion,
- execute code,
- check semantic errors,
- check whether names are defined.

`is_valid(edit)` should compile and validate the plan, returning `false` for validation failures. It may still throw for programmer errors such as invalid argument types.

---

## 18. Display safety

`display(edit)` should:

1. Compile the ordered `EditPlan`.
2. Print its diff.
3. Print validation errors, if any.
4. Store a `DisplayedPlan` in the edit.

The plan hash should include enough information to detect any meaningful change between display and apply:

- flattened edit order,
- ordered primitive operation trace,
- modified paths,
- path moves across the ordered sequence,
- old/new text hashes,
- intermediate text hashes and tracked block-location state when they affect later handle resolution,
- resolved replacement spans at each step,
- create/move/delete operations in order,
- parse modes,
- validation status.

For a `Combine`, changing the order of child edits must change the plan hash, even if the final text would coincidentally be the same.

`string(edit)` may generate a diff, but must not mark the edit as displayed.

`displayed!(edit, true)` should compile and store the current ordered plan without printing it. It bypasses visual display only. It should not bypass validation, path preconditions, plan hashing, ordered handle resolution, or file-change checks.

`displayed!(edit, false)` clears the displayed marker.

---

## 19. Applying edits

`apply!(edit)` should:

1. Check that a displayed marker exists.
2. Check that the displayed plan was valid.
3. Check that path conditions still hold.
4. Compile the ordered plan again from the current filesystem/cache state.
5. Verify that the fresh ordered plan hash matches the displayed plan hash.
6. Validate again.
7. Apply filesystem operations and content writes in a safe order consistent with the ordered plan.
8. Refresh/reindex affected caches.
9. Report success.

If anything changed since display, refuse:

`error("file changed since edit was displayed; display the edit again")`

Application must not silently reinterpret handles differently from the displayed ordered plan. If recompilation produces different intermediate handle resolutions, different path states, or different final file contents, the plan hash must differ and application must fail.

### File operation behavior

`CreateFile`:

- Parent directory must exist at the point the create operation is reached in the ordered plan.
- The file must not already exist in the current virtual path state.
- It does not create parent directories.
- It validates UTF-8.
- It validates Julia syntax if parse mode is Julia.
- Later ordered edits may modify, move, or delete the created file.

`MoveFile`:

- Old path must exist in the current virtual path state.
- New path must not exist in the current virtual path state.
- Parent of new path must exist.
- If the old path is cached, the logical file key is preserved and virtual handles to that file move with it.
- Later ordered edits to handles from that file resolve at the new virtual path.

`DeleteFile`:

- Path must exist in the current virtual path state.
- It invalidates all virtual handles for the corresponding logical file for the remainder of the plan.
- Later ordered edits to those handles fail.
- After successful application, public handles for the deleted logical file are invalidated.

### Transactionality

There is no true cross-file transactionality.

Before writing anything, validate all final files, ordered path conditions, and the displayed plan hash. During application, use atomic content writes where possible. If a later filesystem operation fails, report partial failure clearly.

Because ordered plans may include create, move, delete, and content edits to the same logical file, application should use the ordered operation trace to choose a safe execution sequence. It must preserve the displayed final result and must not expose a different interpretation of the ordered edits.

---

## 20. Cache update and reindexing after apply

After a successful CodeEdit-applied edit, update caches using the ordered plan rather than generic heuristic reindexing whenever possible. Reparse each affected file only after the full ordered edit sequence has been applied successfully.

For each affected logical file:

1. Start from the old cached handle records.
2. Replay the successful ordered plan’s handle-preservation decisions.
3. Parse final file contents.
4. Update public handle records according to the final virtual handle bindings.
5. Invalidate handles that became invalid during the ordered plan.
6. Assign new handles to new unmatched final blocks.
7. Fall back to generic reindexing only for surviving blocks not resolved by the ordered plan.

Recommended deterministic rules:

- `Replace(h, code)` keeps `h` bound to the replacement range for the remainder of the ordered plan when that tracking is unambiguous.
- If tracked preservation of `Replace(h, code)` becomes ambiguous, invalidate `h` for the remainder of the ordered plan.
- `Delete(h)` invalidates `h`, except EOF delete is a no-op.
- `InsertBefore` / `InsertAfter` preserve the target handle when the ordered edit tracking still leaves its block location unambiguous.
- `MoveFile` preserves handles for the moved logical file and updates their path.
- `DeleteFile` invalidates all handles for the deleted logical file.
- Unedited blocks preserve their old handle ids when line shifts are unambiguous.

Invalid handles never become valid again. This applies both during virtual planning and after cache update.

---

## 21. External reindexing

Reindexing is needed when files are modified outside CodeEdit.

Trigger:

- Before serving cached data, compare the current file stamp with the cached stamp.
- If changed, call `reindex(path)` automatically.

Public API:

```julia
reindex()
reindex(path)
```

Algorithm:

1. Parse the new file.
2. Match old blocks to new blocks:
   - exact text match if unique,
   - otherwise nearby old line range with similar content,
   - otherwise invalidate.
3. Preserve matched handle ids.
4. Assign new ids to new unmatched blocks.
5. Invalid handles never become valid again.

Similarity should remain simple. For example:

```text
score = text_similarity - line_distance_penalty
```

If two candidates are too close, invalidate rather than guess.

---

## 22. Diff and display

Implement a stable classic line diff in `diff.jl`.

Requirements:

- plain text only,
- no color,
- deterministic output,
- stable enough for tests.

A simple LCS-based line diff is acceptable.

### Handle display

Normal handle:

```text
# foo.jl 1 - 3:
function foo(x)
    x + 1
end
```

EOF handle:

```text
# foo.jl EOF:
```

Invalid handle:

```text
#invalid
```

### Set/vector display

A `Set{Handle}` display should sort by:

1. filepath,
2. first line,
3. last line,
4. handle id.

A one-element vector should display the contained handle in full. Longer vectors may display an overview.

### Edit display

For content edits:

```text
Edit modifies foo.jl:
2c2
<     x + 1
---
>     x + 2
```

For file creation:

```text
Edit creates bar.jl:
...
```

For move:

```text
Edit moves old.jl -> new.jl
```

For delete file:

```text
Edit deletes old.jl
```

For combined edits, group output by operation/file.

If validation fails, show the diff and then errors:

```text
Validation errors:
- Julia file could not be parsed: foo.jl
```

Displaying an invalid edit marks it as displayed but `apply!` must still refuse because the displayed plan is invalid.

---

## 23. Search

Implement:

```julia
search(handles, needle)
search(path, needle; parse_as=:auto)
search(paths, needle; parse_as=:auto)
search(root, glob, needle; includes=false, parse_as=:auto)

search(handles, trace)
search(handles, exception)
```

String search is:

```julia
filter(h -> occursin(needle, string(h)), handles)
```

Return a `Set{Handle}`.

### Stacktrace matching

Use file and line number.

A handle matches if any stack frame line lies inside `lines(handle)`.

Prefer file identity when available; fall back to path comparison.

Also implement:

```julia
Base.occursin(handle::Handle, trace)
```

### Exception search caveat

In Julia, exception objects do not always carry usable backtraces by themselves.

`search(handles, exception)` should only work when a usable trace can be recovered. Prefer documenting explicit stacktrace usage:

```julia
try
    f()
catch err
    search(handles("src"), catch_backtrace())
end
```

---

## 24. Method integration

Implement:

```julia
Handle(method::Method)
```

Behavior:

1. Check `method.file`.
2. Check `method.line`.
3. Reject REPL/generated/unavailable source.
4. Construct:

```julia
Handle(String(method.file), method.line)
```

Throw:

```julia
ArgumentError("source information unavailable")
```

when source information is not usable.

---

## 25. Error policy

Use standard errors initially:

- `ArgumentError` for invalid user input or unparsable files.
- `ErrorException` for invalid edit application.
- `SystemError`/I/O errors from filesystem operations.

Avoid custom exception types until callers need to distinguish cases.

Examples:

```julia
throw(ArgumentError("Julia file could not be parsed: $path"))
throw(ArgumentError("source information unavailable"))
error("edit has not been displayed")
error("displayed edit was invalid")
error("file changed since edit was displayed; display the edit again")
error("overlapping edits to $path")
error("cannot write through symlink path: $path")
```

---

## 26. Testing plan

### Parsing

- simple functions,
- assignments,
- imports,
- exports,
- constants,
- macros,
- includes,
- top-level `begin`, `let`, `quote`, `if`, `for`, `while`,
- semicolon-separated expressions where parser gives clear boundaries,
- comments attached to following block,
- docstrings,
- stacked docstrings,
- modules split into header/body/footer,
- nested modules,
- EOF block,
- empty file,
- file without final newline,
- CRLF file,
- mixed line endings,
- invalid syntax,
- invalid UTF-8,
- text paragraphs.

### Handles

- `Handle(path, line, pos)`,
- Unicode character positions,
- query in whitespace returns next block,
- query after last block returns EOF,
- EOF handle,
- handle display,
- invalid handle behavior,
- handle identity with `===`,
- alias paths to same file,
- parse mode change invalidates old handles.

### Edits

- replace,
- delete,
- insert before,
- insert after,
- insert without automatic newline,
- EOF replace/insert/delete behavior,
- combined edits,
- combined edits with syntactically invalid intermediate states but valid final states,
- overlapping edit rejection,
- duplicate handle edit rejection,
- ambiguous same-location insertion rejection,
- syntax validation failure,
- non-Julia UTF-8 validation.

### Display/apply safety

- `display(edit)` enables apply,
- REPL/show display marks edit as displayed,
- `string(edit)` does not mark edit as displayed,
- changed file after display causes refusal,
- changed path existence after display causes refusal,
- `displayed!(edit, true)` stores plan without printing,
- `displayed!(edit, false)` clears marker,
- invalid edit cannot be applied.

### Filesystem

- create file,
- create file parent missing,
- create file destination exists,
- move file,
- move file parent missing,
- move destination exists,
- delete file,
- delete missing file,
- content edit atomic write,
- mode preservation where supported,
- symlink write rejection or explicit tested behavior,
- atomic write changes inode but preserves logical cache.

### Reindexing

- edit before handle shifts line numbers,
- exact block match preserves handle,
- nearby similar block preserves handle when unambiguous,
- ambiguous duplicate block invalidates,
- deleted block invalidates,
- replaced block handle preserved after CodeEdit edit when clear,
- invalid handle never becomes valid again.

### Search/methods

- string search,
- search by path,
- search by root/glob,
- recursive include search,
- stacktrace search,
- `Base.occursin(handle, trace)`,
- `Handle(method)`,
- unavailable method source error.

---

## 27. Suggested implementation order

1. `types.jl`
2. `spans.jl`
3. `files.jl`
4. `state.jl`
5. UTF-8 validation and line index helpers
6. text parser
7. basic Julia parser for top-level blocks
8. cache loading and parse dispatch
9. handle constructors and handle display
10. EOF handles
11. simple search
12. edit types and constructors
13. single-edit in-memory replacement planning
14. validation
15. diff display
16. displayed-plan safety for single edits
17. `apply!` with atomic writes for single edits
18. deterministic cache update after single edits
19. generic reindexing
20. virtual file state model for ordered planning
21. ordered `Combine`
22. file create/move/delete
23. recursive include traversal
24. method and stacktrace integration
25. parser polish: modules, docstrings, comments, semicolons
26. filesystem edge cases: symlinks, aliases, mode bits, CRLF

This order gives a usable vertical slice early while isolating the higher-risk ordered planning and virtual handle-tracking logic.

---

## 28. Main implementation risks

### 1. JuliaSyntax node details

Module splitting, docstring detection, and comments may require careful parser-tree inspection. Keep this logic isolated in `parse_julia.jl`.

### 2. Byte offsets versus character positions

Julia string indexing is byte-based. Public positions are character/codepoint-based. Centralize conversion helpers and test Unicode.

### 3. Atomic writes and file identity

Atomic replacement may change inode/device identity. Use logical `FileKey` for cache identity and `FileID` only as current filesystem identity.

### 4. Displayed edit safety

A boolean `displayed=true` is too weak. Store a plan fingerprint and path preconditions.

### 5. Reindexing ambiguity

Do not guess. If two blocks could plausibly match one old handle, invalidate.

### 6. Symlink behavior

Atomic rename through symlink paths is dangerous. Reject symlink writes initially unless realpath behavior is explicitly designed and tested.

### 7. Line-ending preservation

Do not normalize during parsing, display, or diffing. Edits insert exactly supplied text.

### 8. Ordered Combine semantics

Ordered `Combine` semantics are substantially more complex than simultaneous snapshot semantics.

The planner must maintain a virtual filesystem state and virtual handle registry while interpreting child edits left to right. Handles must track their blocks through insertions, replacements, deletions, and file moves without reparsing intermediate states, but only when this can be done unambiguously.

The implementation should be conservative:

- update tracked block locations directly from ordered edits,
- allow intermediate states that are not syntactically valid,
- reparse only after the full ordered sequence when validating final contents,
- preserve handles only when there is a clear corresponding final block,
- invalidate rather than guess,
- reject later uses of invalidated handles,
- include ordered intermediate state in the displayed-plan hash.

Do not mutate the real cache or public handle records during planning. Public state changes only after successful `apply!`.

---

## 29. Architecture summary

The intended architecture is:

public API objects  
↓  
cache + handle registry  
↓  
parser-specific block detection  
↓  
ordered edit planning with virtual file and handle state  
↓  
validation  
↓  
display/fingerprint  
↓  
safe apply  
↓  
cache update/reindex

The central discipline is to keep these phases separate:

- parsing does not edit,
- handles do not perform filesystem operations,
- planning tracks ordered virtual state but does not mutate public state,
- display does not apply,
- validation does not execute code,
- apply does not silently re-plan a different edit,
- reindexing invalidates rather than guessing dangerously.
