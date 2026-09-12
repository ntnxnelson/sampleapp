'use strict';

var express = require('express');
var mongoose = require('mongoose');

var FIELDS = ['rank', 'peak', 'elevation', 'state', 'range'];
// Fields matched exactly; everything else is a case-insensitive substring match.
var EXACT_FIELDS = ['rank'];

function escapeRegExp(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

module.exports = function (Peak) {
    var router = express.Router();

    // Fail fast with a clear message instead of letting Mongoose buffer the
    // query for 10 seconds when the database is unreachable.
    router.use(function (req, res, next) {
        if (mongoose.connection.readyState !== 1) {
            return res.status(503).json({ error: 'Database is not connected' });
        }
        next();
    });

    // GET /api/peaks            -> all peaks, highest elevation first (the seed data's order)
    // GET /api/peaks?state=colo -> filtered (rank exact, other fields substring, case-insensitive)
    router.get('/', async function (req, res, next) {
        try {
            var filter = {};
            FIELDS.forEach(function (field) {
                var value = req.query[field];
                if (typeof value !== 'string' || value.trim() === '') {
                    return;
                }
                value = value.trim();
                filter[field] = EXACT_FIELDS.indexOf(field) > -1
                    ? value
                    : new RegExp(escapeRegExp(value), 'i');
            });
            var peaks = await Peak.find(filter)
                .collation({ locale: 'en', numericOrdering: true })
                .sort({ elevation: -1, rank: 1 });
            res.json(peaks);
        } catch (err) {
            next(err);
        }
    });

    // POST /api/peaks  (JSON or form-encoded body)
    router.post('/', async function (req, res, next) {
        try {
            var doc = {};
            FIELDS.forEach(function (field) {
                if (req.body[field] !== undefined && req.body[field] !== null) {
                    doc[field] = String(req.body[field]);
                }
            });
            var saved = await new Peak(doc).save();
            res.status(201).json(saved);
        } catch (err) {
            if (err.name === 'ValidationError') {
                return res.status(400).json({ error: err.message });
            }
            next(err);
        }
    });

    return router;
};
