#!/usr/bin/env node

"use strict";

var fs   = require('fs'),
    http = require('http'),
    url  = require('url'),
    util = require('util'),
    logger = require('./logger'),
    service_checker = require('./service_checker');

var config = function (config) {
  var beacon_url  = url.parse(config.beaconUrl);
  var beacon_host = beacon_url.hostname;
  var beacon_port = beacon_url.port || 80;

  var update_interval = config.updateInterval || 15000;

  var verbose = config.verbose === true; // Don't allow bogus values

  return {
    services : function() { return config.services; },

    beaconHost : function() { return beacon_host; },
    beaconPort : function() { return beacon_port; },

    updateInterval : function() { return update_interval; },
    heartbeatTimeout : function() {
        return config.heartbeatTimeout ||
          Math.ceil(this.updateInterval * 4 / 3000);
      },
    heartStopCommand : function() {
        return 'hb(' + this.heartbeatTimeout() + ',"' +
          (config.heartStopCommand && config.heartStopCommand() || 'r.p') +
          '")';
      },

    verbose : function() { return verbose; }
  };
}(require('./config'));

if(config.verbose()) {
  logger.enableLogging();
}

fs.readdirSync('checkers').forEach(function(module) {
    try {
      require('./checkers/' + module);
    } catch(exception) {
      logger.log('Problem reading module: "' + module + '": ' +
                 exception.message + exception.stack);
    }
  });

process.on('uncaughtException', function(err) {
  logger.log('Caught exception: ' + err.message + '\n' + err.stack);
});

function sendCommand(cmd) {
  var beacon = http.createClient(config.beaconPort(), config.beaconHost());
  var request = beacon.request('POST', '/lights',
    { 'Host' : config.beaconHost(),
      'Content-Type' : 'text/plain',
      'Content-Length' : cmd.length });

  if(config.verbose()) {
    request.on('response', function(response) {
        var result = '';
        response.on('data', function(chunk) { result += chunk; });
        response.on('end', function() { logger.log('response: ' + result); });
      });
  }

  logger.log('cmd: ' + cmd);

  request.write(cmd);
  request.end();
}

var checkers = config.services().map(function(service) {
  var checker = service_checker.getChecker(service.name);
  if(checker) {
    return new checker(service);
  } else {
    logger.log('Invalid service: "' + service.name + '"');
    return null;
  }
}).filter(function(e) { return e; });

function checkStuff() {
  var totalChecks = checkers.length;
  var commands = [];
  checkers.forEach(function(checker) {
      checker.check(function(command) {
        commands.push(command);
        if(--totalChecks === 0) {
          sendCommand(commands.join('.')+';');
        }
      });
    });
}

sendCommand(config.heartStopCommand() + ';');
checkStuff();

setInterval(checkStuff, config.updateInterval());
