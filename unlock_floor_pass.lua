local batch = require('lib_locksmith_batch')

return batch.mode('floor_pass', {
    usage = 'targets:<types>',
    desc = 'Unjam every floor container, then unlock every floor container',
})
