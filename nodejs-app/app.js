#!/usr/bin/env node
'use strict';

var express = require('express');
var mongoose = require('mongoose');
var os = require('os');
var Peak = require('./models/peakModel');

var app = express();
var port = parseInt(process.env.PORT, 10) || 3000;

// MongoDB connection. Set MONGODB_HOST to the address of the database VM,
// or MONGODB_URI for full control over the connection string.
var mongodbHost = process.env.MONGODB_HOST || '127.0.0.1';
var mongodbPort = process.env.MONGODB_PORT || '27017';
var mongodbDb = process.env.MONGODB_DB || 'demodb';
var mongoUri = process.env.MONGODB_URI ||
    ('mongodb://' + mongodbHost + ':' + mongodbPort + '/' + mongodbDb);
var RETRY_MS = 5000;

function redact(uri) {
    return uri.replace(/\/\/[^@/]+@/, '//***@');
}

// Keep trying until the database is reachable so the service comes up cleanly
// even if the MongoDB VM finishes booting after this one. Once connected, the
// driver handles reconnects on its own.
function connectWithRetry() {
    mongoose.connect(mongoUri, { serverSelectionTimeoutMS: 5000 })
        .then(function () {
            console.log('Connected to MongoDB at ' + redact(mongoUri));
        })
        .catch(function (err) {
            console.error('MongoDB connection to ' + redact(mongoUri) + ' failed: ' +
                err.message + '. Retrying in ' + (RETRY_MS / 1000) + 's.');
            setTimeout(connectWithRetry, RETRY_MS);
        });
}
connectWithRetry();

mongoose.connection.on('disconnected', function () {
    console.warn('MongoDB disconnected');
});
mongoose.connection.on('reconnected', function () {
    console.log('MongoDB reconnected');
});

app.disable('x-powered-by');
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(function (req, res, next) {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
    if (req.method === 'OPTIONS') {
        return res.sendStatus(204);
    }
    next();
});

app.use('/api/peaks', require('./routes/peakRoutes')(Peak));
app.use('/api/info', require('./routes/infoRoutes')());

// Health check for load balancers and automation: 200 when the database is
// connected, 503 otherwise.
app.get('/api/health', function (req, res) {
    var dbConnected = mongoose.connection.readyState === 1;
    res.status(dbConnected ? 200 : 503).json({
        status: dbConnected ? 'ok' : 'degraded',
        database: dbConnected ? 'connected' : 'disconnected',
        databaseHost: mongodbHost,
        hostname: os.hostname(),
        uptime: Math.round(process.uptime())
    });
});

app.get('/', function (req, res) {
    res.send('API is functional.');
});

app.use(function (req, res) {
    res.status(404).json({ error: 'Not found' });
});

// eslint-disable-next-line no-unused-vars
app.use(function (err, req, res, next) {
    console.error(err);
    res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

var server = app.listen(port, function () {
    console.log('Peaks API listening on port ' + port);
});

function shutdown(signal) {
    console.log(signal + ' received, shutting down');
    server.close(function () {
        mongoose.connection.close(false).then(function () {
            process.exit(0);
        });
    });
    setTimeout(function () { process.exit(1); }, 5000).unref();
}
process.on('SIGTERM', function () { shutdown('SIGTERM'); });
process.on('SIGINT', function () { shutdown('SIGINT'); });

module.exports = server;
