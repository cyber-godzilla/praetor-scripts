local S = {}

S.falx_stun_roll = {'swing the haft upwards'}

S.falx_stun = {'reels back, stunned by the blow'}

-- Critical-hit stuns are emitted as a standalone status line immediately
-- before the attack result rather than as part of the dedicated stun text.
S.falx_target_stunned = '^* is stunned!$'

S.falx_fall = {'stumbles and falls'}

S.falx_drag_fail = {'* must be standing.'}

S.falx_ev_exit = {
    'falls unconscious', 'stands up',
    'You can only perform that action on a prone target.',
    'launches upwards and backwards onto',
}

return S
