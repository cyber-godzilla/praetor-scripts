local batch = require('lib_locksmith_batch')

return batch.mode('carry', {
    usage = 'targets:<types> from:<source|here> done:<container|here> reject:<container|here> open:true|false [stow:<container>]',
    desc = 'Unlock carried containers and put or drop them by result',
})
