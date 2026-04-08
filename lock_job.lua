--[[
Accepts a locksmithing job from an NPC.
Accepts one argument, the name of the NPC (Not shopkeeper)
/mode lock_job citizen|trader|sailor
]]
local strings = require('lib_strings')
local locksmithing = require('lib_locksmithing')

local M = {}

function M.on_start(args)
    -- args is the customers list passed from board mode or /job command
    local customers = {}
    for _, c in ipairs(args) do customers[#customers + 1] = c end
    state.set('customers', customers)

    -- Greet first customer
    if #customers > 0 then
        local customer = table.remove(customers, 1)
        state.set('customer', customer)
        state.set('customers', customers)
        local greeting = random_item(locksmithing.greetings)
        send('say to ' .. customer .. ' ' .. greeting, 500)
    end
end

M.reactions = {
    -- Customer arrivals: queue them even during a job
    {
        match = locksmithing.sailor_arrival,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'sailor'
            state.set('customers', customers)
        end,
    },
    {
        match = locksmithing.scholar_arrival,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'scholar'
            state.set('customers', customers)
        end,
    },
    {
        match = locksmithing.citizen_arrival,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'citizen'
            state.set('customers', customers)
        end,
    },
    {
        match = locksmithing.merchant_arrival,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'merchant'
            state.set('customers', customers)
        end,
    },
    {
        match = locksmithing.trader_arrival,
        action = function()
            local customers = state.get('customers') or {}
            customers[#customers + 1] = 'trader'
            state.set('customers', customers)
        end,
    },

    -- Job type detection: craft lockpick (tin)
    {
        match = 'I need a lockpick. A tin one.',
        action = function()
            state.set('job_type', 'craft')
            state.set('is_crafted', false)
            state.set('metal_type', 'tin')
            state.set('broken_wire', false)
            local customer = state.get('customer')
            send('say to ' .. customer .. ' yes')
            send('buy wire', 5500)
        end,
    },
    -- Craft lockpick (bronze)
    {
        match = 'I need a lockpick. A bronze one.',
        action = function()
            state.set('job_type', 'craft')
            state.set('is_crafted', false)
            state.set('metal_type', 'bronze')
            state.set('broken_wire', false)
            local customer = state.get('customer')
            send('say to ' .. customer .. ' yes')
            send('buy wire', 5500)
        end,
    },
    -- Craft lockpick (iron)
    {
        match = 'I need a lockpick. An iron one.',
        action = function()
            state.set('job_type', 'craft')
            state.set('is_crafted', false)
            state.set('metal_type', 'iron')
            state.set('broken_wire', false)
            local customer = state.get('customer')
            send('say to ' .. customer .. ' yes')
            send('buy wire', 5500)
        end,
    },
    -- Wire substance selection
    {
        match = 'That comes in the following substances',
        action = function() send(state.get('metal_type')) end,
    },
    -- Wire purchase confirmation
    {
        match = 'Would you still like a thin length of wire',
        action = function() send('y') end,
    },
    -- Wire placed on counter
    {
        match = '* places a thin length',
        action = function() send('get wire') end,
    },
    -- Took wire: fashion pick
    {
        match = 'You take a thin length',
        action = function() send('fashion lockpick from wire') end,
    },
    -- Took broken wire: stash it
    {
        match = 'You take a broken thin length',
        action = function()
            send('put broken in my sack')
            state.set('broken_wire', false)
        end,
    },
    -- Put broken wire away: buy new
    {
        match = 'You put a broken',
        action = function() send('buy wire') end,
    },
    -- Pick fashioned successfully
    {
        match = 'and work it into',
        action = function() state.set('is_crafted', true) end,
    },
    -- Wire snapped
    {
        match = 'wire snaps! Its functionality gone',
        action = function() state.set('broken_wire', true) end,
    },
    -- Offered item: next customer or back to board
    {
        match = 'You offer',
        action = function()
            local customers = state.get('customers') or {}
            if #customers == 0 then
                set_mode('board')
                return
            end
            -- Reset job state
            state.set('job_type', nil)
            state.set('broken_wire', false)
            state.set('is_crafted', false)
            state.set('is_installed', false)
            state.set('is_jammed', false)
            state.set('is_locked', false)
            state.set('metal_type', nil)
            state.set('lock_target', nil)
            -- Next customer
            local customer = table.remove(customers, 1)
            state.set('customer', customer)
            state.set('customers', customers)
            send('say to ' .. customer .. ' hello', 1100)
        end,
    },
    -- Unbusy: state-dependent actions
    {
        match = strings.unbusy,
        action = function()
            local job = state.get('job_type')
            local customer = state.get('customer')
            if job == 'craft' then
                if state.get('broken_wire') then
                    send('get broken')
                else
                    send('offer ' .. state.get('metal_type') .. ' to ' .. customer)
                end
                return
            end
            local target = state.get('lock_target')
            if not target then return end
            if job == 'unlock' then
                if state.get('is_jammed') then
                    send('unjam ' .. target .. ' with lock')
                    return
                end
                if state.get('is_locked') then
                    send('unlock ' .. target .. ' with lock')
                    return
                end
                send('offer ' .. target .. ' to ' .. customer)
                return
            end
            if job == 'lock' then
                if not state.get('is_locked') then
                    send('lock ' .. target .. ' with lock')
                    return
                end
                send('offer ' .. target .. ' to ' .. customer)
                return
            end
            if job == 'install' then
                if not state.get('is_installed') then
                    send('install mech in ' .. target)
                    return
                end
                send('offer ' .. target .. ' to ' .. customer)
                return
            end
        end,
    },
    -- Unlock request
    {
        match = 'Can you pick it open?',
        action = function()
            if not state.get('job_type') then
                state.set('job_type', 'unlock')
                state.set('is_locked', true)
                local customer = state.get('customer')
                send('say to ' .. customer .. ' yes')
            end
        end,
    },
    -- Lock request
    {
        match = 'Can you pick it locked?',
        action = function()
            if not state.get('job_type') then
                state.set('job_type', 'lock')
                state.set('is_locked', false)
                local customer = state.get('customer')
                send('say to ' .. customer .. ' yes')
            end
        end,
    },
    -- Already done
    {
        match = 'It is already',
        action = function()
            local target = state.get('lock_target')
            local customer = state.get('customer')
            if target and customer then
                send('offer ' .. target .. ' to ' .. customer)
            end
        end,
    },
    -- Jammed lock request
    {
        match = "I think it's jammed",
        action = function()
            if not state.get('job_type') then
                state.set('job_type', 'unlock')
                state.set('is_locked', true)
                state.set('is_jammed', true)
                local customer = state.get('customer')
                send('say to ' .. customer .. ' yes')
            end
        end,
    },
    -- Install request
    {
        match = 'Can you install a lock in it for me?',
        action = function()
            if not state.get('job_type') then
                state.set('job_type', 'install')
                local customer = state.get('customer')
                send('say to ' .. customer .. ' yes')
            end
        end,
    },
    -- Unjammed
    {
        match = 'You feel an obstruction release',
        action = function() state.set('is_jammed', false) end,
    },
    -- Unlocked
    {
        match = 'You hear a click as the tumbler mechanism releases',
        action = function() state.set('is_locked', false) end,
    },
    -- Locked
    {
        match = 'You hear a click as a tumbler mechanism closes.',
        action = function() state.set('is_locked', true) end,
    },
    -- Need lockpick
    {
        match = {'You must be holding', "You don't see any", "You can't unlock", "You can't lock"},
        action = function() send('get my lockpick') end,
    },
    -- Got lockpick: resume job
    {
        match = {'You take * lockpick', 'You are already carrying * lockpick'},
        action = function()
            local job = state.get('job_type')
            local target = state.get('lock_target')
            if not target then return end
            if job == 'lock' then
                send('lock ' .. target .. ' with lock')
            elseif job == 'unlock' then
                send('unlock ' .. target .. ' with lock')
            end
        end,
    },
    -- Lock is jammed (discovered during unlock)
    {
        match = 'This lock is jammed',
        action = function()
            state.set('is_jammed', true)
            local target = state.get('lock_target')
            send('unjam ' .. target .. ' with lock')
        end,
    },
    -- Customer hands us a chest
    {
        match = 'hands you * chest',
        action = function()
            state.set('lock_target', 'chest')
            local job = state.get('job_type')
            if job == 'lock' then
                send('lock chest with lock')
            elseif job == 'unlock' then
                send('unlock chest with lock')
            elseif job == 'install' then
                send('buy tumbler')
            end
        end,
    },
    -- Customer hands us a coffer
    {
        match = 'hands you a coffer',
        action = function()
            state.set('lock_target', 'coffer')
            local job = state.get('job_type')
            if job == 'lock' then
                send('lock coffer with lock')
            elseif job == 'unlock' then
                send('unlock coffer with lock')
            elseif job == 'install' then
                send('buy tumbler')
            end
        end,
    },
    -- Customer hands us a scroll tube
    {
        match = 'hands you a bronze scroll tube',
        action = function()
            state.set('lock_target', 'tube')
            local job = state.get('job_type')
            if job == 'lock' then
                send('lock tube with lock')
            elseif job == 'unlock' then
                send('unlock tube with lock')
            elseif job == 'install' then
                send('buy tumbler')
            end
        end,
    },
    -- Customer hands us a trunk
    {
        match = 'hands you a heavy wooden trunk',
        action = function()
            state.set('lock_target', 'trunk')
            local job = state.get('job_type')
            if job == 'lock' then
                send('lock trunk with lock')
            elseif job == 'unlock' then
                send('unlock trunk with lock')
            elseif job == 'install' then
                send('buy tumbler')
            end
        end,
    },
    -- Tumbler box placed
    {
        match = "* places a small wooden box labeled 'Tumbler' *",
        action = function() send('get box') end,
    },
    -- Got tumbler box
    {
        match = "You take a small wooden box labeled 'Tumbler'",
        action = function() send('open box') end,
    },
    -- Opened tumbler box
    {
        match = "You open a small wooden box labeled 'Tumbler', revealing a tumbler mechanism and a small tin key",
        action = function()
            local target = state.get('lock_target')
            send('empty box into ' .. target)
        end,
    },
    -- Emptied tumbler box
    {
        match = "You empty the contents of a small wooden box labeled 'Tumbler' into",
        action = function() send('discard box') end,
    },
    -- Confirm discard
    {
        match = "Are you sure you want to throw a small wooden box labeled 'Tumbler' away? (y/n)",
        action = function() send('y') end,
    },
    -- Discarded box
    {
        match = "You discard a small wooden box labeled 'Tumbler'",
        action = function() send('get mechanism') end,
    },
    -- Got mechanism
    {
        match = 'You take a tumbler mechanism',
        action = function()
            local target = state.get('lock_target')
            send('install mechanism in ' .. target)
        end,
    },
    -- Mechanism installed
    {
        match = 'You set the placement of the new tumbler mechanism with great care',
        action = function() state.set('is_installed', true) end,
    },
}

return M
