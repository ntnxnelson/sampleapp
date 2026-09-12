'use strict';

var mongoose = require('mongoose');

var peakSchema = new mongoose.Schema({
    rank:      { type: String, trim: true },
    peak:      { type: String, trim: true, required: [true, 'peak name is required'] },
    elevation: { type: String, trim: true },
    state:     { type: String, trim: true },
    range:     { type: String, trim: true }
}, {
    versionKey: false
});

// Model name "Peak" maps to the "peaks" collection, which is what
// db/seed.js seeds.
module.exports = mongoose.model('Peak', peakSchema);
