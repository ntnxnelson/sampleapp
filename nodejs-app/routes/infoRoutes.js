'use strict';

var express = require('express');
var os = require('os');

// Returns the first non-loopback IPv4 address, or 127.0.0.1 if none is found.
function primaryIPv4() {
    var interfaces = os.networkInterfaces();
    var names = Object.keys(interfaces);
    for (var i = 0; i < names.length; i++) {
        var addrs = interfaces[names[i]] || [];
        for (var j = 0; j < addrs.length; j++) {
            var a = addrs[j];
            // Node < 18 reports family as the string 'IPv4', Node >= 18.0 as the number 4.
            if ((a.family === 'IPv4' || a.family === 4) && !a.internal) {
                return a.address;
            }
        }
    }
    return '127.0.0.1';
}

module.exports = function () {
    var router = express.Router();

    // GET /api/info -> where this API instance is running (shown on the web page)
    router.get('/', function (req, res) {
        res.json({
            ip: primaryIPv4(),
            hostname: os.hostname(),
            nodeVersion: process.version
        });
    });

    return router;
};
