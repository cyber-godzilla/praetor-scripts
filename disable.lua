--[[
Disable - Don't do anything
]]
local M = {}

M.desc = 'Stop all automation'

function M.on_start(args)
    log('Automation disabled')
end

M.reactions = {}

return M
