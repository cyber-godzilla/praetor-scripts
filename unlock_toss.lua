local batch = require('lib_locksmith_batch')

return batch.mode('toss', {
    usage = 'targets:<types> from:<source|here> done:<direction> reject:<direction> open:true|false [stow:<container>]',
    desc = 'Unlock carried containers and toss them by result',
})
