local C = {}

local WATCHDOG_OVERLAP_MS = 1000

-- Could use input from other weapon users for weapon-specific kill strings
C.kill = {
    'You slit ', 'and expires.', 'Your blade cuts cleanly through',
    'in the head repeatedly', 'A *armband* falls from *',
}

-- Strings you would see when there's nobody left to attack
C.no_targets = {
    "^You can't *", '^It has left the area.', "^You don't see any",
    '^You are not currently engaging anyone',
}

-- Strings that indicate you've been approached or have successfully approached.
C.approached = {
    'You stop next to', 'stops next to you', 'Gripping your * falx hard, you pull',
    'moves towards you', 'You are already engaged', 'You advance toward',
}

-- New enemy arrives, or you need to approach
C.arrival = {
    'arrives', 'walks in', 'You are not close enough',
    'oozes in', 'reanimates',
}

-- Separate from arrival: this means "too far to attack", should send adv1.
-- Generally, strings that indicate you have to use melee advance or a weapon move to adjust who is approached to you.
C.not_close_enough = {'is not close enough'}

-- Strings that indicate you have to wield your weapon
C.rewield = {
    'You fumble, losing your grip', 'You must be wielding your weapon in two hands',
    "You can't do that right now", 'You must be wielding a weapon to attack',
}

-- Player attack roll strings: only these indicate a real attack was made.
-- Used to determine when to rotate the attack list on [Success:].
-- Definitely need more skills added here
C.attack_roll = {
    'You thrust your', 'You lean into your forward shoulder, striking',
    'You turn and lean into your shoulder', 'You dip one hand then shoot an upward',
    'throwing a straight strike', 'You slide one foot back',
    'You slide your rear foot back', 'You lean forward, striking',
    'You lift your back leg up', 'You jab at',
    'You bring down your', 'You slash horizontally at',
    'Using the flat of your', 'You make a quick stabbing motion at',
    'You bash', 'Tilting your shield forward',
    'You miss', 'you draw your arm back halfway',
    'you whirl around', 'With blinding speed, you chop down',
    'you steadily step sideways towards', 'You jab tentatively',
    'Using the center of your', 'Without stopping your',
    'you let loose a quick side strike', 'Using your stave like a long club',
    'you step forward and pivot slightly', 'With a quick forward rotation, you',
    'With a fluid motion, you bring your', 'You twist your torso and extend',
    'You hold your', 'You grip your',
    'You lean forward slashing at', 'You lean forward, slashing at',
    'You swing the blade of your', 'You tilt the blade of your',
    'swing wildly', 'You take a wide grip on your',
    'You slide your rear foot to the side', 'bring it swiftly down while spinning',
    'You raise your', 'You thrust forward',
    'You swing your', 'You slash diagonally',
    'You lift the blade of your', 'Sweeping the blade of your',
    'You extend your sword arm wide and thrust', 'You slam your',
    'You take a step forward, pushing off of your', 'You lift your',
    'You dip the blade of your', 'You hit',
    'You snap your', 'You twist your body',
    'You crouch slightly and bring up the ring of your',
    'You extend the chain and snap your hand forward',
    'You release your', 'You step forward with a quick jab',
    'You drop to one knee, flinging the spinning blade',
}

function C.rotate(actions)
    if #actions > 1 then
        table.insert(actions, table.remove(actions, 1))
    end
end

-- Suppress reaction-driven attacks while the game has explicitly reported no
-- target, and briefly after a watchdog kick. The latter prevents a stale
-- unbusy from immediately duplicating the watchdog's recovery command.
function C.can_attack()
    if state.get('combat_no_targets') then return false end
    local kicked = state.get('watchdog_kicked_at')
    if not state.get('watchdog_firing') and kicked and time.since(kicked) < WATCHDOG_OVERLAP_MS then
        return false
    end
    return true
end

function C.send_attack(command, delay)
    if not C.can_attack() then return false end
    send(command, delay)
    state.set('last_command_time', time.now())
    return true
end

function C.attack()
    local actions = state.get('actions_list')
    if actions and #actions > 0 then return C.send_attack(actions[1]) end
    return false
end

-- Watchdog: kick attack_fn if no command sent in stall_ms.
-- Recovers from stalls where no [Success:] or unbusy arrives
-- (e.g. 'You are already engaging' followed by silence).
function C.start_watchdog(attack_fn, stall_ms, check_ms)
    attack_fn = attack_fn or C.attack
    stall_ms = stall_ms or 8000
    check_ms = check_ms or 3000
    state.set('last_command_time', time.now())
    state.set('combat_no_targets', false)
    state.set('watchdog_kicked_at', nil)
    state.set('watchdog_firing', false)
    local id = set_interval(function()
        local last = state.get('last_command_time') or 0
        if not state.get('combat_no_targets') and time.since(last) > stall_ms then
            log('combat watchdog: stall detected, kicking attack')
            state.set('watchdog_kicked_at', time.now())
            state.set('watchdog_firing', true)
            attack_fn()
            state.set('watchdog_firing', false)
            -- Reset regardless so we wait a full stall_ms before firing again,
            -- even if attack_fn short-circuited without sending.
            state.set('last_command_time', time.now())
        end
    end, check_ms)
    state.set('watchdog_id', id)
end

function C.stop_watchdog()
    local id = state.get('watchdog_id')
    if id then
        clear_timer(id)
        state.set('watchdog_id', nil)
    end
    state.set('watchdog_firing', false)
end

function C.on_kill()
    metrics.inc('kills')
    state.set('target_ko', false)
    state.set('approached', false)
end

function C.on_ko()
    if state.get('do_kill') then state.set('target_ko', true) end
end

function C.try_kill()
    if state.get('do_kill') and state.get('target_ko') then
        C.send_attack('k1')
        return true
    end
    return false
end

function C.approach()
    state.set('combat_no_targets', false)
    state.set('approached', true)
    send('app1')
    state.set('last_command_time', time.now())
end

function C.on_approached(attack_fn)
    state.set('combat_no_targets', false)
    state.set('approached', true)
    local attack = attack_fn or C.attack
    attack()
end

function C.on_no_targets()
    state.set('combat_no_targets', true)
    state.set('target_ko', false)
    state.set('approached', false)
end

-- Check if text contains any pattern from a list. Asterisks use the same
-- ordered wildcard semantics as reaction patterns; everything else is a
-- literal substring.
function C.text_matches(text, patterns)
    if not text or not patterns then return false end
    for _, p in ipairs(patterns) do
        if not p:find('*', 1, true) then
            if text:find(p, 1, true) then return true end
        else
            local position = 1
            local matched = true
            for part in p:gmatch('[^*]+') do
                local first, last = text:find(part, position, true)
                if not first then
                    matched = false
                    break
                end
                position = last + 1
            end
            if matched then return true end
        end
    end
    return false
end

-- Handle [Success:] in macro modes. The game sends kill, KO, and attack
-- results all as [Success:] lines, so this one handler must dispatch them.
-- attack_fn is an optional function to call for anti-idle recovery
-- (defaults to C.attack if nil).
-- Returns true if it handled the text (kill or KO), false for normal flow.
function C.handle_success(text, attack_fn)
    local player_attack = C.text_matches(text, C.attack_roll)
    if player_attack and text and text:find('Critical Hit!', 1, true) then
        metrics.inc('crits')
    end
    -- Check for kill
    if C.text_matches(text, C.kill) then
        C.on_kill()
        return true
    end
    -- Check for KO
    if text and text:find('falls unconscious', 1, true) then
        C.on_ko()
        return true
    end
    -- Only rotate on player attack rolls, not stun/drag/ev/etc
    if player_attack then
        local actions = state.get('actions_list')
        if actions then C.rotate(actions) end
    end
    -- Anti-idle: if 5+ seconds since last command, trigger an attack
    -- to prevent getting stuck in combat doing nothing.
    local last = state.get('last_command_time') or 0
    if time.since(last) > 5000 then
        if attack_fn then
            attack_fn()
        else
            C.attack()
        end
    end
    return false
end

return C
