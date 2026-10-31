local strings = require('lib_strings')

local C = {}

local WATCHDOG_OVERLAP_MS = 1000
local ADVANCE_RETRY_MS = 3000
local MUST_STAND_RETRY_MS = 30000
local DEATH_EVIDENCE_TTL_MS = 3000
local active_attack_fn
local clear_interpose_recovery

-- Death evidence observed in combat logs. Some enemies emit an item drop and a
-- disappearance line before the attack result, so every evidence form must
-- reach on_kill() and be deduplicated there rather than incrementing directly.
-- Keep these patterns narrow: ordinary critical-hit prose often sounds fatal.
C.kill = {
    'You slit ', 'and expires.',
    'Your blade cuts cleanly through * body slowly slides apart as * dies.',
    'in the head repeatedly', '^A *armband* falls from *.$',
    'With massive force, you bring down your',
    'You thrust your * through * heart.',
    'drops dead after', "'s skull is parted by",
    'falls in a heap, dead.', 'puncturing * heart!',
    'crushes through muscle, arteries and bone, until the head of * before suddenly crashing to the ground at your feet.',
    'Savage blow to * head!',
    '^As * falls, a brilliant flash of light fills the area,*',
    '^The corpse of * falls back among the piles of the dead with a flash,*',
}

-- Strings you would see when there's nobody left to attack
C.no_targets = {
    "^You can't * the corpse of *", '^It has left the area.', "^You don't see any",
    '^You are not currently engaging anyone',

    -- Broad macro-target expressions can resolve to equipment or dropped
    -- weapons after the last NPC leaves.  The watchdog otherwise retries the
    -- maneuver every few seconds until another NPC arrives.  Keep these
    -- patterns limited to observed combat commands so unrelated "You can't"
    -- responses do not pause combat.
    "^You can't offchop *", "^You can't offpivot *",
    "^You can't rotchop *", "^You can't sweepcleave *",
    "^You can't onslaught *", "^You can't offcrush *",
    "^You can't pollsmash *", "^You can't advance *",
}

C.target_report = {
    '^Your macro target is *.$', '^Your new macro target is *.$',
}

-- Strings that indicate you've been approached or have successfully approached.
C.approached = {
    'You stop next to', 'stops next to you', 'Gripping your * falx hard, you pull',
    'You are already engaged', 'You advance toward',
}

-- Enemy movement can wake a stopped rotation, but must not send another attack
-- for every duplicate movement line while combat is already active.
C.enemy_approached = 'moves towards you'

-- New enemy arrives, or you need to approach
C.arrival = {
    'arrives', 'walks in', 'You are not close enough',
    'oozes in', 'reanimates', 'charges in', 'charge in',
    'rushes in', 'rush in', 'lopes in',
    'steps out of the nearby shadows', 'flies in',
}

-- Separate from arrival: this means "too far to attack", should send adv1.
-- Generally, strings that indicate you have to use melee advance or a weapon move to adjust who is approached to you.
C.not_close_enough = {
    'is not close enough', "but can't get close", "You'll have to retreat first",
}

-- The posture command is a Praetor input variable, so it must go through the
-- typed-input pipeline rather than send(), which would transmit it literally.
C.posture_ready = '^You are once again able to change combat postures.$'
C.posture_restored = {
    '^Combat mode changed to *',
    '^You are already in a * stance!$',
}
C.stun_recovered = 'You are no longer stunned.'
C.stood_up = {'^You stand up.$', '^You are already standing.$'}

function C.restore_posture()
    state.set('posture_restore_pending', true)
    praetor_script('${target_posture:normal}')
    state.set('last_command_time', time.now())
end

function C.on_posture_restored()
    state.set('posture_restore_pending', false)
end

function C.retry_posture()
    if not state.get('posture_restore_pending') then return false end
    C.restore_posture()
    return true
end

function C.on_stun_recovered()
    state.set('combat_no_targets', false)
    local knocked_down_at = state.get('must_stand_pending_at')
    if not knocked_down_at then return end
    if time.since(knocked_down_at) <= MUST_STAND_RETRY_MS then
        send('stand')
        state.set('last_command_time', time.now())
    else
        state.set('must_stand_pending_at', nil)
    end
end

local SELF_RECOVERED_TO_FEET = {
    'onto your feet', 'back to your feet', 'back up to your feet',
}

function C.requires_stand(text)
    if not text then return true end
    for _, phrase in ipairs(SELF_RECOVERED_TO_FEET) do
        if text:find(phrase, 1, true) then return false end
    end
    return C.text_matches(text, strings.must_stand)
end

function C.on_must_stand(text)
    if text and not C.requires_stand(text) then return false end
    state.set('must_stand_pending_at', time.now())
    send('stand')
    state.set('last_command_time', time.now())
    return true
end

function C.on_stood_up()
    state.set('must_stand_pending_at', nil)
end

function C.on_not_close_enough()
    local pending = state.get('advance_pending_at')
    if pending and time.since(pending) < ADVANCE_RETRY_MS then return false end
    state.set('advance_pending_at', time.now())
    send('adv1', 0)
    state.set('last_command_time', time.now())
    return true
end

-- Strings that indicate you have to wield your weapon
C.rewield = {
    'You fumble, losing your grip', 'You must be wielding your weapon in two hands',
    "You can't do that right now", 'You must be wielding a weapon',
    'You must be actively wielding a weapon in each hand to execute this maneuver.',
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

    -- Archery
    'You fire a', 'You quickly raise your', 'You take careful aim',

    -- Brawling and cestus
    'You punch at', 'You kick your leg out at', 'You try to kick',
    'You stomp', 'You swing a cestus-covered fist',
    'You send a heavy, underhand punch',
    'Arm extended, you pivot backwards',
    'With both arms extended, you spin in place',

    -- Additional weapon families
    'You deftly lunge at', 'You lead with your', 'You tentatively jab',
    'Using both arms, you bring your', 'You make a wide horizontal',
    'You slide your lower hand', 'You plant your feet into the ground',
    'Flicking your',

    -- Spears
    'Lifting it in one hand', 'With a quick snapping motion',
    'you swing the butt around', 'You twist your wrists and sweep',
    'Expertly darting the blade', 'You slash horizontally',
    'You make a quick stabbing', 'You slide your grip',
    'Sliding your front leg back',
    'Stepping forward aggressively', 'You lean forward, feigning a thrust',

    -- Pardelian One-Handed Swords
    'Targeting the flank, you jab at',
    'Ducking your entire body weight behind your shield',
    'Tilting your * shield on a vertical axis',
    'Flipping the tip of your', 'Casting your * shield towards one side',
    'You make a wide, heavy-handed, slashing attack',
    'Raising your * shield above your head',
    'Stepping forward with the lead foot', 'Making a wide, false slash',
    'You snap out your arm',

    -- Two-Handed Crushing
    'You surge forward, driving your',
    'In a vicious lateral swing, you aim your',
    'You plant your feet firmly, draw back your',
    'With deliberate force, you raise your',
    'Spinning swiftly, you smash your',

    -- Falcata and Falx
    'You weave behind', 'You dig your blade into', 'You lunge at',
    'You duck under', 'You dive forward and roll over your shoulder',
    'You drop your weight, slamming', 'You crouch low, swinging your',

    -- Dual Daggers
    'You dart forward, driving a rapid jab',
    'You drop your weight into a vicious downward stab',
    'You whip your knife down', 'You step in and drive your daggers',
    'From your reverse grip, you drive both points',
    'You dart in and out with blinding speed', 'You drop low and slash at',
    'In a blinding staccato rhythm, you drive', 'You hook the guard of',
    'You stutter-step into a false thrust',

    -- Whips
    'You curl your wrist into a tight loop',

    -- Hoplite Combat
    'With a deft twist, you drive your', 'Slamming your shield into',
    'Using your shield to balance', 'Rising from a low crouch',
    'You push', 'You sling your', 'With a bold lunge, you stab forward',
    'You step to the side suddenly', 'Reversing your grip, you swing your',
    'Crouching low, you swing your', 'You lunge forward',
    'You lean forward, feigning a stab',

    -- Dual Axes: hit and miss variants observed in game logs. Several moves
    -- use a different opening sentence when they miss, so both are required
    -- for the attack rotation to advance reliably.
    'You pivot and chop with your', 'You pivot smoothly on your back foot',
    'Stepping inside * guard, you slam the blunt poll of your',
    'You pivot sharply on your lead foot', 'You pivot and jab the horn of your',
    'You step in and swing your', 'You drive the heavy poll of your',
    'You drive the poll of your', 'You pivot smoothly on your heels',
    'Shifting your footing quickly and dropping your guard, you snap your',
    'Stepping inside * guard, you deliver a rapid, alternating sequence',
    'You sweep your', 'You bring both your', 'You raise both your',
    'You step forward to strike',
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
    if state.get('posture_restore_pending') then return false end
    if state.get('combat_no_targets') then return false end
    if state.get('interpose_waiting_for') then return false end
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
    active_attack_fn = attack_fn
    stall_ms = stall_ms or 8000
    check_ms = check_ms or 3000
    state.set('last_command_time', time.now())
    state.set('combat_no_targets', false)
    state.set('must_stand_pending_at', nil)
    state.set('posture_restore_pending', false)
    state.set('watchdog_kicked_at', nil)
    state.set('watchdog_firing', false)
    state.set('advance_pending_at', nil)
    state.set('approach_pending', false)
    state.set('interpose_target', nil)
    state.set('interpose_original_target', nil)
    state.set('interpose_waiting_for', nil)
    state.set('interpose_resume_after_query', false)
    state.set('interpose_last_protected', nil)
    state.set('interpose_last_blocker', nil)
    state.set('recent_death_evidence', nil)
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
    local original_target = state.get('interpose_original_target')
    if original_target and C.in_interpose_recovery() then
        send('@mtarg ' .. original_target, 0)
    end
    local id = state.get('watchdog_id')
    if id then
        clear_timer(id)
        state.set('watchdog_id', nil)
    end
    state.set('must_stand_pending_at', nil)
    state.set('posture_restore_pending', false)
    state.set('watchdog_firing', false)
    state.set('recent_death_evidence', nil)
    clear_interpose_recovery()
    active_attack_fn = nil
end

local function mark_command()
    state.set('last_command_time', time.now())
end

local function clean_target_name(name)
    if not name then return nil end
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    name = name:gsub('^[Aa][Nn]? ', ''):gsub('^[Tt]he ', '')
    if name == '' then return nil end
    return name
end

local target_joiners = {
    a = true, an = true, the = true, with = true, of = true, by = true,
    ['in'] = true, on = true, from = true, covered = true, wearing = true,
    wielding = true, carrying = true,
}

local target_roles = {
    archer = true, bandit = true, guard = true, rogue = true, ruffian = true,
}

local function target_words(name)
    local words = {}
    for raw_word in (name or ''):gmatch('%S+') do
        local word = raw_word:gsub('^[%p]+', ''):gsub('[%p]+$', '')
        if word ~= '' then
            table.insert(words, {value = word, key = word:lower()})
        end
    end
    return words
end

-- Character combat macros append mtarg directly to commands whose target
-- grammar accepts one identifying word. Pick the first meaningful blocker word
-- that does not also describe the protected NPC.
-- This keeps "mud-covered bandit" short while avoiding the observed failure
-- where both "bandit with hairy arms" and "bandit with a leathery face" were
-- reduced to the useless selector "bandit".
local function target_selector(blocker, protected)
    local protected_words = {}
    for _, word in ipairs(target_words(protected)) do
        protected_words[word.key] = true
    end

    local meaningful = {}
    for _, word in ipairs(target_words(blocker)) do
        if not target_joiners[word.key] then
            table.insert(meaningful, word.value)
            if not protected_words[word.key] then return word.value end
        end
    end

    -- Identical descriptions cannot be distinguished lexically. Do not put an
    -- ordinal in mtarg: the combat macros already supply their own leading
    -- action selector, and an indexed mtarg makes the game parse that selector
    -- as the target. Prefer a descriptive word over the shared NPC role; after
    -- an interpose, proximity resolves that description to the adjacent blocker.
    for _, word in ipairs(meaningful) do
        if not target_roles[word:lower()] then return word end
    end
    if meaningful[1] then return meaningful[1] end
    return nil
end

local function parse_interpose(text)
    if not text then return nil, nil end
    local outcome = text
    local success_start = outcome:find(strings.success, 1, true)
    if success_start then
        local _, close = outcome:find('] ', success_start, true)
        if close then outcome = outcome:sub(close + 1) end
    end
    local protected, blocker = outcome:match(
        '^You move toward (.-), but are interposed by (.-)%.$'
    )
    return clean_target_name(protected), clean_target_name(blocker)
end

function C.is_interpose(text)
    local protected, blocker = parse_interpose(text)
    return protected ~= nil and blocker ~= nil
end

function C.in_interpose_recovery()
    return state.get('interpose_target') ~= nil
        or state.get('interpose_waiting_for') ~= nil
end

local function retarget(target, waiting_for)
    if not target then return false end
    state.set('interpose_waiting_for', waiting_for)
    send('@mtarg ' .. target, 0)
    mark_command()
    return true
end

clear_interpose_recovery = function()
    state.set('interpose_target', nil)
    state.set('interpose_original_target', nil)
    state.set('interpose_waiting_for', nil)
    state.set('interpose_resume_after_query', false)
    state.set('interpose_last_protected', nil)
    state.set('interpose_last_blocker', nil)
end

local function restore_original_target()
    if state.get('interpose_waiting_for') == 'query'
        and not state.get('interpose_original_target') then
        state.set('interpose_resume_after_query', true)
        return true
    end
    state.set('target_ko', false)
    state.set('advance_pending_at', nil)
    state.set('approached', false)

    local original = state.get('interpose_original_target')
    if original then
        -- The original setting may be a pipe expression or an indexed target;
        -- restore it byte-for-byte instead of treating it as an NPC name.
        return retarget(original, 'restore')
    end

    clear_interpose_recovery()
    state.set('combat_no_targets', true)
    return false
end

-- An interpose leaves the player next to the blocker while every configured
-- combat macro still points at the protected target. Save the user's macro
-- target and focus the blocker. After one recovery kill, restore the original
-- target and let app1 resolve the next opponent from that expression again.
function C.on_interpose(text)
    local protected, blocker = parse_interpose(text)
    if not protected or not blocker then return false end

    if state.get('interpose_target') == blocker
        and state.get('interpose_last_protected') == protected
        and state.get('interpose_last_blocker') == blocker then
        if not state.get('interpose_waiting_for') then
            retarget(target_selector(blocker, protected), 'switch')
        end
        return true
    end

    state.set('interpose_target', blocker)
    state.set('interpose_last_protected', protected)
    state.set('interpose_last_blocker', blocker)
    state.set('target_ko', false)
    state.set('combat_no_targets', false)
    state.set('advance_pending_at', nil)
    state.set('approach_pending', false)
    state.set('approached', true)

    if not state.get('interpose_original_target') then
        state.set('interpose_waiting_for', 'query')
        send('@mtarg', 0)
        mark_command()
        return true
    end
    retarget(target_selector(blocker, protected), 'switch')
    return true
end

local function parse_target_report(text)
    if not text then return nil end
    return text:match('^Your new macro target is (.*)%.$')
        or text:match('^Your macro target is (.*)%.$')
end

function C.on_target_report(text)
    local waiting = state.get('interpose_waiting_for')
    if not waiting then return false end
    local target = parse_target_report(text)
    if not target or target == '' then return false end

    if waiting == 'query' then
        state.set('interpose_original_target', target)
        if state.get('interpose_resume_after_query') then
            state.set('interpose_resume_after_query', false)
            return restore_original_target()
        end
        return retarget(
            target_selector(
                state.get('interpose_target'),
                state.get('interpose_last_protected')
            ),
            'switch'
        )
    end

    if waiting == 'switch' then
        state.set('interpose_waiting_for', nil)
        state.set('approached', true)
        -- A watchdog tick may have overlapped the target query. Its kick did
        -- not send while recovery was pending, so it must not debounce the
        -- first real attack against the blocker.
        state.set('watchdog_kicked_at', nil)
        local attack = active_attack_fn or C.attack
        attack()
        return true
    end

    if waiting == 'restore' then
        state.set('interpose_waiting_for', nil)
        clear_interpose_recovery()
        C.approach()
        return true
    end
    return false
end

local function normalize_death_target(target)
    if not target then return nil end
    target = target:lower():gsub('^%s+', ''):gsub('%s+$', '')
    target = target:gsub('^the corpse of ', '')
    target = target:gsub('^the ', ''):gsub('^an? ', '')
    target = target:gsub('[%s%.!]+$', '')
    if target == '' then return nil end
    return target
end

local function add_death_signal(signals, target, source)
    table.insert(signals, {
        target = normalize_death_target(target),
        source = source,
    })
end

-- Return each independently countable death signal on a line. The fatal-result
-- patterns below are deliberately based on confirmed log sequences; phrases
-- such as "deadly slash", "fatal jab", and "collapses in shock" also occur in
-- non-fatal critical hits and must not be accepted on their own.
local function death_signals(text)
    local signals = {}
    if not text then return signals end

    local target = text:match('^A .-armband.- falls from (.-)%.$')
    if target then add_death_signal(signals, target, 'drop') end

    target = text:match('^As (.-) falls, a brilliant flash of light fills the area,')
    if target then add_death_signal(signals, target, 'disappear') end

    target = text:match('^The corpse of (.-) falls back among the piles of the dead with a flash,')
    if target then add_death_signal(signals, target, 'disappear') end

    for name in text:gmatch(
        'Your blade cuts cleanly through (.-), nearly cleaving.-body slowly slides apart as.-dies%.'
    ) do
        add_death_signal(signals, name, 'result')
    end
    for name in text:gmatch('Critical Hit!%s+([Aa]n? .-) drops dead after') do
        add_death_signal(signals, name, 'result')
    end
    for name in text:gmatch("Critical Hit!%s+([Aa]n? .-)'s skull is parted by") do
        add_death_signal(signals, name, 'result')
    end
    for name in text:gmatch(
        "across the top of (.-)'s head relieves.-before.-falls in a heap, dead%."
    ) do
        add_death_signal(signals, name, 'result')
    end
    for name in text:gmatch("crush (.-)'s sternum.-puncturing [^%s]+ heart!") do
        add_death_signal(signals, name, 'result')
    end
    for name in text:gmatch(
        'until the head of (.-) rises a bit before suddenly crashing to the ground at your feet%.'
    ) do
        add_death_signal(signals, name, 'result')
    end
    for name in text:gmatch("Savage blow to (.-)'s head!") do
        add_death_signal(signals, name, 'result')
    end
    for name in text:gmatch("You thrust your .- through (.-)'s heart%.") do
        add_death_signal(signals, name, 'result')
    end

    -- Older weapon-specific finishers were recorded before target extraction
    -- was added. They are one-death results and do not have the undead drop /
    -- disappearance echoes found in the parsed log corpus.
    if #signals == 0 and (
        text:find('You slit ', 1, true)
        or text:find('and expires.', 1, true)
        or text:find('in the head repeatedly', 1, true)
        or text:find('With massive force, you bring down your', 1, true)
    ) then
        add_death_signal(signals, nil, 'result')
    end

    return signals
end

function C.is_death(text)
    return #death_signals(text) > 0
end

-- A single death can produce drop -> disappearance -> result (the result may
-- arrive last). Match evidence by normalized target and source for a short
-- window. Separate deaths of identically-described enemies still count: a
-- second signal from the same source opens a second evidence record.
function C.track_deaths(text, parsed_signals)
    local signals = parsed_signals or death_signals(text)
    if #signals == 0 then return 0 end

    local recent = state.get('recent_death_evidence') or {}
    local active = {}
    for _, event in ipairs(recent) do
        if event.at and time.since(event.at) <= DEATH_EVIDENCE_TTL_MS then
            table.insert(active, event)
        end
    end

    local added = 0
    for _, signal in ipairs(signals) do
        local duplicate
        if signal.target then
            for _, event in ipairs(active) do
                if event.target == signal.target and not event.sources[signal.source] then
                    duplicate = event
                    break
                end
            end
        end

        if duplicate then
            duplicate.sources[signal.source] = true
            duplicate.at = time.now()
        else
            local sources = {}
            sources[signal.source] = true
            table.insert(active, {
                target = signal.target,
                sources = sources,
                at = time.now(),
            })
            metrics.inc('kills')
            added = added + 1
        end
    end
    state.set('recent_death_evidence', active)
    return added
end

function C.on_kill(text, parsed_signals)
    C.track_deaths(text, parsed_signals)
    state.set('target_ko', false)
    state.set('approached', false)
    if C.in_interpose_recovery() then restore_original_target() end
end

function C.on_ko(text)
    local recovery_target = state.get('interpose_target')
    if recovery_target and text and not text:find(recovery_target, 1, true) then
        return false
    end
    if state.get('do_kill') then
        state.set('target_ko', true)
    elseif C.in_interpose_recovery() then
        restore_original_target()
    end
    return true
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
    state.set('approached', false)
    state.set('approach_pending', true)
    state.set('advance_pending_at', nil)
    send('app1')
    mark_command()
end

function C.on_approached(attack_fn)
    state.set('combat_no_targets', false)
    state.set('approached', true)
    state.set('approach_pending', false)
    state.set('advance_pending_at', nil)
    local attack = attack_fn or C.attack
    attack()
end

local function confirm_approached()
    state.set('combat_no_targets', false)
    state.set('approached', true)
    state.set('approach_pending', false)
    state.set('advance_pending_at', nil)
end

function C.on_enemy_approached(attack_fn)
    if state.get('approached') and not state.get('combat_no_targets') then
        return false
    end
    C.on_approached(attack_fn)
    return true
end

function C.on_no_targets(text)
    if C.in_interpose_recovery() then
        -- A response from the command that triggered recovery can arrive after
        -- the macro-target query/switch was queued. It says nothing about the
        -- new target and must not poison the recovery state.
        if not state.get('interpose_waiting_for') then
            restore_original_target()
        end
        return true
    end
    state.set('combat_no_targets', true)
    state.set('target_ko', false)
    state.set('approached', false)
    return true
end

-- Record every piece of the player's armor that completely absorbs a hit.
-- A single multi-strike result can name the same or different pieces more than
-- once, so scan the whole line instead of using one greedy match.
function C.track_absorb(text)
    if not text then return 0 end

    local absorb
    local tracked = 0
    for armor in text:gmatch('Your ([^%.!?]-) absorbs? the impact of the blow') do
        if armor ~= '' then
            absorb = absorb or state.get('armor_absorb') or {}
            absorb[armor] = (absorb[armor] or 0) + 1
            tracked = tracked + 1
        end
    end
    if absorb then state.set('armor_absorb', absorb) end
    return tracked
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

-- Success lines mix player and enemy rolls. Attack descriptions usually begin
-- in the player's voice ("You ...") or switch to it after an introductory
-- clause (", you ..."). Requiring that perspective prevents broad weapon
-- patterns such as spear openings from treating enemy attacks as ours.
function C.is_player_attack(text)
    if not text then return false end
    local outcome = text
    local success_start = outcome:find(strings.success, 1, true)
    if success_start then
        local _, close = outcome:find('] ', success_start, true)
        if close then outcome = outcome:sub(close + 1) end
    end
    local player_voice = outcome:sub(1, 4) == 'You '
        or outcome:find(', you ', 1, true) ~= nil
    return player_voice and C.text_matches(outcome, C.attack_roll)
end

-- Record one confirmed player maneuver and every critical-hit marker it
-- produced. Some multi-target attacks emit more than one marker in one line.
-- force allows a confirmed player result whose prose is not yet represented
-- in attack_roll (for example, a newly observed killing-blow description).
function C.track_player_action(text, force)
    if not text or not text:find(strings.success, 1, true) then return false end
    if not force and not C.is_player_attack(text) then return false end

    metrics.inc('actions')
    local position = 1
    while true do
        local _, last = text:find('Critical Hit!', position, true)
        if not last then break end
        metrics.inc('crits')
        position = last + 1
    end
    return true
end

-- Handle [Success:] in macro modes. The game sends kill, KO, knockdown, and
-- attack results all as [Success:] lines, so this one handler must dispatch
-- them. In particular, success reactions run before each mode's must_stand
-- reaction, and only the first matching reaction runs.
-- attack_fn is an optional function to call for anti-idle recovery
-- (defaults to C.attack if nil).
-- rotate_player_attack can be false for weapon-specific submodes whose attack
-- text overlaps the normal rotation (for example, falx eviscerate).
-- Returns true if it handled the text (kill, KO, must stand, or distance
-- recovery), false for normal flow.
function C.handle_success(text, attack_fn, rotate_player_attack)
    if rotate_player_attack == nil then rotate_player_attack = true end
    -- Enemy attacks and player attacks share the success prefix, and a single
    -- result may contain more than one absorption message.
    C.track_absorb(text)
    if C.on_interpose(text) then return true end
    -- Preserve combat state even when a compound line also requires standing.
    local parsed_deaths = death_signals(text)
    local killed = #parsed_deaths > 0
    local player_attack = C.is_player_attack(text)
    -- Killing blows are confirmed player actions even when their prose is not
    -- yet represented in attack_roll. Standalone backup kill messages do not
    -- have a success prefix and therefore are ignored by the tracker.
    C.track_player_action(text, player_attack or killed)

    local knocked_down = C.requires_stand(text)
    local knocked_out = text and text:find('falls unconscious', 1, true)
    local not_close_enough = C.text_matches(text, C.not_close_enough)
    local approached = C.text_matches(text, C.approached)
    if killed then
        C.on_kill(text, parsed_deaths)
    end
    if knocked_out then
        C.on_ko(text)
    end
    if knocked_down then
        C.on_must_stand(text)
        return true
    end
    if not_close_enough then
        C.on_not_close_enough()
        return true
    end
    if approached then
        confirm_approached()
        return true
    end
    if killed or knocked_out then
        return true
    end

    -- Only rotate on player attack rolls, not stun/drag/ev/etc
    if player_attack and rotate_player_attack then
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
