--[[
This mode rotates through locksmithing skills on the board, but also accepts and completes jobs automatically.
Pass argument no_jobs if you just want to rotate skills on the board:
/mode board no_jobs

Don't use this for running jobs unless you're able to do all of the jobs, including lockpick fashioning.

**ASSUMES YOU HAVE A SILVER LOCKPICK!**
]]
local strings = require('lib_strings')
local locksmithing = require('lib_locksmithing')

local M = {}

local board_actions = {'unlock board with lock', 'study board', 'recall lock tumbler'}

function M.on_start(args)
    local do_jobs = true
    for _, arg in ipairs(args) do
        if arg == 'no_job' or arg == 'no_jobs' then do_jobs = false end
    end
    state.set('do_jobs', do_jobs)
    state.set('board_actions', {board_actions[1], board_actions[2], board_actions[3]})
    state.set('customers', {})
    send(board_actions[1])
end

M.reactions = {
    -- Customer arrivals: queue them up (only when doing jobs)
    {
        match = locksmithing.sailor_arrival,
        condition = function() return state.get('do_jobs') end,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'sailor'
            state.set('customers', customers)
        end,
    },
    {
        match = locksmithing.scholar_arrival,
        condition = function() return state.get('do_jobs') end,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'scholar'
            state.set('customers', customers)
        end,
    },
    {
        match = locksmithing.citizen_arrival,
        condition = function() return state.get('do_jobs') end,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'citizen'
            state.set('customers', customers)
        end,
    },
    {
        match = locksmithing.merchant_arrival,
        condition = function() return state.get('do_jobs') end,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'merchant'
            state.set('customers', customers)
        end,
    },
    {
        match = locksmithing.trader_arrival,
        condition = function() return state.get('do_jobs') end,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'trader'
            state.set('customers', customers)
        end,
    },
    -- Unbusy: check for customers or rotate board actions
    {
        match = strings.unbusy,
        action = function()
            if state.get('do_jobs') then
                local customers = state.get('customers') or {}
                if #customers >= 1 then
                    set_mode('lock_job', customers)
                    return
                end
            end
            local acts = state.get('board_actions')
            if acts and #acts > 1 then
                table.insert(acts, table.remove(acts, 1))
            end
            if acts and #acts > 0 then send(acts[1]) end
        end,
    },
    -- Can't unlock board
    {
        match = "You can't unlock",
        action = function() send('get my silver lockpick') end,
    },
    -- Took lockpick
    {
        match = 'You take * lockpick',
        action = function()
            local acts = state.get('board_actions')
            if acts and #acts > 0 then send(acts[1]) end
        end,
    },
    -- Must be holding / don't see
    {
        match = {'You must be holding', "You don't see any", "You can't lock"},
        action = function() send('get my lockpick') end,
    },
}

return M
