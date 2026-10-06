--[[
Completion handoffs for modes that run to a natural end.

Supported suffixes:
  after_mode:<mode> [args...]  -- switch modes, passing every remaining token
  after_do:<command...>        -- disable automation, then send one game command
  after_ps:<script...>         -- disable automation, then run PraetorScript

The first completion suffix starts the payload, so it and everything after it
must be the final portion of the current mode invocation:
  /mode loot hand after_mode:wagon romulus
  /mode idle after_do:look in wagon
  /mode idle after_ps:stand&&climb wall;;look

Mode handoffs can nest because their remaining tokens are passed verbatim:
  /mode loot hand after_mode:wagon romulus after_mode:idle

The old `after:<mode>` form remains a compatibility alias. Unlike after_mode,
it consumes only its own token and cannot carry target-mode arguments.
]]
local A = {}

local function clear_target()
    state.set('after_kind', nil)
    state.set('after_mode', nil)
    state.set('after_mode_args', nil)
    state.set('after_payload', nil)
    state.set('after_error', nil)
end

local function tail_tokens(args, index, first)
    local tokens = {}
    if first ~= '' then tokens[#tokens + 1] = first end
    for i = index + 1, #args do
        tokens[#tokens + 1] = args[i]
    end
    return tokens
end

local function invalid(message)
    state.set('after_kind', 'invalid')
    state.set('after_error', message)
    log('lib_after: ' .. message)
end

-- Strip the completion suffix from the current mode's arguments and remember
-- its target. New-style suffixes consume every token after them as payload.
function A.parse(args)
    args = args or {}
    clear_target()

    local rest = {}
    for index, arg in ipairs(args) do
        if type(arg) ~= 'string' then
            rest[#rest + 1] = arg
        else
            local mode = arg:match('^after_mode:(.*)$')
            local command = arg:match('^after_do:(.*)$')
            local script = arg:match('^after_ps:(.*)$')
            local legacy = arg:match('^after:(.*)$')

            if mode ~= nil then
                local tokens = tail_tokens(args, index, mode)
                if #tokens == 0 then
                    invalid('after_mode: needs a mode name')
                else
                    state.set('after_kind', 'mode')
                    state.set('after_mode', tokens[1])
                    table.remove(tokens, 1)
                    state.set('after_mode_args', tokens)
                end
                break
            elseif command ~= nil then
                local tokens = tail_tokens(args, index, command)
                if #tokens == 0 then
                    invalid('after_do: needs a game command')
                else
                    state.set('after_kind', 'do')
                    state.set('after_payload', table.concat(tokens, ' '))
                end
                break
            elseif script ~= nil then
                local tokens = tail_tokens(args, index, script)
                if #tokens == 0 then
                    invalid('after_ps: needs a PraetorScript expression')
                else
                    state.set('after_kind', 'ps')
                    state.set('after_payload', table.concat(tokens, ' '))
                end
                break
            elseif legacy ~= nil then
                if legacy == '' then
                    invalid('after: needs a mode name')
                else
                    state.set('after_kind', 'mode')
                    state.set('after_mode', legacy)
                    state.set('after_mode_args', {})
                end
            else
                rest[#rest + 1] = arg
            end
        end
    end
    return rest
end

-- Execute the configured handoff. With no explicit suffix, switch to fallback
-- (default `disable`) exactly as before.
function A.finish(fallback)
    local kind = state.get('after_kind')

    if kind == 'mode' then
        set_mode(state.get('after_mode'), state.get('after_mode_args') or {})
        return
    end

    if kind == 'do' then
        local command = state.get('after_payload')
        -- Switching first is intentional: a mode switch clears commands queued
        -- by the outgoing mode, while this command must survive the handoff.
        set_mode('disable')
        send(command)
        return
    end

    if kind == 'ps' then
        local script = state.get('after_payload')
        set_mode('disable')
        if type(praetor_script) ~= 'function' then
            log('lib_after: this Praetor version does not expose praetor_script()')
            notify('Cannot proceed', 'after_ps requires a newer Praetor version')
            return
        end
        praetor_script(script)
        return
    end

    if kind == 'invalid' then
        set_mode('disable')
        return
    end

    set_mode(fallback or 'disable')
end

return A
