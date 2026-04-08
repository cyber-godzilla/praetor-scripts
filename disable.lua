--[[
Disable - Don't do anything
]]
local M = {}

function M.on_start(args)
    log('Automation disabled')
end

M.reactions = {}

return M
