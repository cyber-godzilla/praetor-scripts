--[[
Get and toss every item of a type in a direction, one at a time.

The direction is the only positional argument; everything else is a
key:value token and may appear in any position:
  what:<item>       -- what to get and toss (default: sack)
  from:<container>  -- get from a container instead of the ground:
                       `get <what> from <from>`
  try_drag:<bool>   -- default false; when true, attempt a
                       `drag <from> <dir>` after every post-toss unbusy,
                       so the source container follows the tossed items
                       once it is light enough to move

/mode toss_sacks north                     <-- Toss all sacks north
/mode toss_sacks down what:pouch           <-- Toss all pouches down
/mode toss_sacks e from:travois try_drag:true
    <-- Empty a travois eastward, dragging it after each toss
/mode toss_sacks east after:wagon          <-- Toss all sacks east, then run wagon
]]
local strings = require('lib_strings')
local after = require('lib_after')

local M = {}

M.usage = '<direction> [what:<item>] [from:<container>] [try_drag:true|false]'
M.desc = 'Get and toss every item of a type in a direction'
M.chains = true

local option_keys = {what = true, from = true, try_drag = true}

-- Consume key:value tokens wherever they sit; the first bare token is the
-- direction. Returns nil plus a message when an argument doesn't make sense.
local function parse_args(args)
    local config = {direction = nil, what = 'sack', from = '', try_drag = false}
    for _, arg in ipairs(args) do
        local key, value = arg:match('^(.-):(.*)$')
        if key and option_keys[key] then
            if key == 'what' then
                if value == '' then return nil, 'what: needs an item' end
                config.what = value
            elseif key == 'from' then
                config.from = value
            elseif key == 'try_drag' then
                if value == 'true' then
                    config.try_drag = true
                elseif value ~= 'false' then
                    return nil, 'try_drag: needs true or false'
                end
            end
        elseif key then
            return nil, 'unknown option "' .. arg .. '"'
        elseif not config.direction then
            config.direction = arg
        end
    end
    if not config.direction then
        return nil, 'requires a direction'
    end
    if config.try_drag and config.from == '' then
        return nil, 'try_drag: needs a from:<container> to drag'
    end
    return config
end

local function send_get()
    local from = state.get('from')
    if from ~= '' then
        send('get ' .. state.get('what') .. ' from ' .. from)
    else
        send('get ' .. state.get('what'))
    end
end

function M.on_start(args)
    args = after.parse(args)

    local config, err = parse_args(args)
    if not config then
        log('toss_sacks mode ' .. err)
        set_mode('disable')
        return
    end

    state.set('direction', config.direction)
    state.set('what', config.what)
    state.set('from', config.from)
    state.set('try_drag', config.try_drag)
    state.set('awaiting', 'take')
    send_get()
end

M.reactions = {
    -- Took one: toss it onward. The toss's unbusy drives the next cycle.
    {
        match = 'You take',
        action = function()
            state.set('awaiting', 'unbusy')
            send('toss ' .. state.get('what') .. ' ' .. state.get('direction'))
        end,
    },
    -- Toss landed: optionally drag the source container after it, then get
    -- the next. The awaiting guard keeps a successful drag's own unbusy from
    -- re-firing this — only the post-toss unbusy counts.
    {
        match = strings.unbusy,
        condition = function()
            return state.get('awaiting') == 'unbusy'
        end,
        action = function()
            state.set('awaiting', 'take')
            if state.get('try_drag') then
                send('drag ' .. state.get('from') .. ' ' .. state.get('direction'))
            end
            send_get()
        end,
    },
    -- Hands are full: a failure, so notify and stop without chaining
    {
        match = 'You must remove',
        action = function()
            notify('Cannot proceed', 'toss_sacks stopped: hands full')
            set_mode('disable')
        end,
    },
    -- Nothing left to get: done
    {
        match = "You don't see",
        action = function()
            notify('Completed', 'toss_sacks finished')
            after.finish()
        end,
    },
}

return M
