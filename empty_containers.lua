--[[
Empty all containers of a type from a container into a container.
Defaults:
- Empty all sacks
- From wagon
- Into wagon
/mode empty_containers sack wagon wagon
/mode empty_containers pouch wagon wagon
etc
]]
local M = {}

function M.on_start(args)
    local item = args[1] or 'sack'
    local source = args[2] or 'wagon'
    local destination = args[3] or 'wagon'
    state.set('item', item)
    state.set('source', source)
    state.set('destination', destination)
    send('get ' .. item .. ' from ' .. source)
end

M.reactions = {
    {
        match = 'You take',
        action = function()
            local item = state.get('item')
            local dest = state.get('destination')
            send('empty ' .. item .. ' into ' .. dest)
        end,
    },
    {
        match = {'You empty', 'has nothing in it'},
        action = function()
            local item = state.get('item')
            send('drop ' .. item)
        end,
    },
    {
        match = 'You drop',
        action = function()
            local item = state.get('item')
            local source = state.get('source')
            send('get ' .. item .. ' from ' .. source)
        end,
    },
    {
        match = "You don't see",
        action = function()
            set_mode('disable')
            notify('Completed', 'emptyContainers finished')
        end,
    },
}

return M
