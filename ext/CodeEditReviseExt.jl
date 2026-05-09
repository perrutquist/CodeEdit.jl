module CodeEditReviseExt

using CodeEdit
using Revise

function __init__()
    CodeEdit.register_post_apply_hook!(:Revise) do
        Revise.revise()
        return nothing
    end

    return nothing
end

end
