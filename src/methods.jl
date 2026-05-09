"""
Return a handle to a Method's source block when source information is available.
"""
function Handle(method::Method)
    file = method.file
    line = method.line

    if file === nothing || line <= 0
        throw(ArgumentError("source information unavailable"))
    end

    path = String(file)

    if isempty(path) || startswith(path, "REPL[") || !isfile(path)
        throw(ArgumentError("source information unavailable"))
    end

    return Handle(path, Int(line))
end
