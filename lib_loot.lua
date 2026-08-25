local L = {}

L.loot = {
    kel_rep = 'retalq|boison|sooty|alanti|iron|bronze helm|bronze mining|triang|towering|gauntlet|manksana|nagoda|katitra',
    kel = 'nagoda|katitra|gauntlet|manksana|retalq|boison|sooty|alanti|iron|bronze|tin|boss|triang|towering',
    bandit = 'mask|boots|armor|pouch|box|neckpouch|bronze|alanti|sooty|iron|boison|retalq|mace|sack',
    metals = 'retalq|boison|alanti|sooty|iron',
    hand =
    'gauntlet|shield|hood|mask|boison|alanti|sooty|mace|dirk|blade|iron|bronze|armor|boot|belt|rawhide|legging|whip|helm|pouch|sack|pteryge|armband|collar',
}

function L.resolve(alias)
    return L.loot[alias] or alias
end

return L
