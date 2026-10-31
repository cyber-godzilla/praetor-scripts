local batch = require('lib_locksmith_batch')

return batch.mode('floor_each', {
    usage = 'targets:<types>',
    desc = 'Unjam and unlock each floor container before moving to the next',
})
