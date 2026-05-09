module CodeEditReviseExt

using CodeEdit
using Revise

function __init__()
    CodeEdit._maybe_revise_callback[] = function ()
        Revise.revise()
        return nothing
    end

    return nothing
end

end
