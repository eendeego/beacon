#!/usr/bin/env node

var http = require('http');
var url = require('url');

var config = function(config) {
  var beacon_url  = url.parse(config.beaconUrl);
  var beacon_host = beacon_url.hostname;
  var beacon_port = beacon_url.port || 80;

  var hudson_url    = url.parse(config.hudsonUrl);
  var hudson_host   = hudson_url.hostname;
  var hudson_port   = hudson_url.port || 80;
  var hudson_secure = hudson_url.protocol == 'https:';
  var hudson_auth   = hudson_url.auth ?
    'Basic ' + new Buffer(hudson_url.auth).toString('base64') :
    undefined;

  var update_interval = config.updateInterval || 15000;

  var verbose = config.verbose === true; // Don't allow bogus values

  return {
    beaconHost : function() { return beacon_host; },
    beaconPort : function() { return beacon_port; },

    hudsonHost   : function() { return hudson_host;   },
    hudsonPort   : function() { return hudson_port;   },
    hudsonSecure : function() { return hudson_secure; },
    hudsonAuth   : function() { return hudson_auth;   },

    updateInterval : function() { return update_interval; },

    verbose : function() { return verbose; },

    hudsonCommand : config.hudsonCommand ||
      function(color, building) {
        return 'bm(15).' + (color == 'green' ? 'g' : 'r') + '.w' +
          (building ? '.bm(3).a' : '');
      },
    initCommand : config.initCommand || function() { return 'g!.w'; },
    heartStopCommand : function() {
        return 'hb(' + (update_interval/1000 + 5) + ',"' +
          (config.heartStopCommand && config.heartStopCommand() || 'r.p') +
          '")';
      }
  };

}(require('./config'));

process.on('uncaughtException', function (err) {
  console.log('Caught exception: ' + err);
});

var v_log;
if(config.verbose()) {
  v_log = function(message) {  
    console.log(message);
  };
} else {
  v_log = function() {};
}

function sendCommand(cmd) {
  var beacon = http.createClient(config.beaconPort(), config.beaconHost());
  var request = beacon.request('POST', '/lights',
    { 'Host' : config.beaconHost(),
      'Content-Type' : 'text/plain',
      'Content-Length' : cmd.length });

  if(config.verbose()) {
    request.on('response', function (response) {
        var result = '';
        response.on('data', function (chunk) { result += chunk; });
        response.on('end', function () { console.log('response: ' + result); });
      });
  }

  v_log('cmd: ' + cmd);

  request.write(cmd);
  request.end();
}

function checkHudson() {
  var hudson = http.createClient(config.hudsonPort(), config.hudsonHost());
  var request_headers = { 'Host' : config.hudsonHost() };
  if(config.hudsonAuth) { request_headers.Authorization = config.hudsonAuth(); }
  var request = hudson.request('GET', '/api/json',
                               request_headers,
                               config.hudsonSecure());

  request.on('response', function (response) {
      var result = '';
      response.on('data', function (chunk) { result += chunk; });
      response.on('end', function () {
          var status = JSON.parse(result);
          var building = false;
          var color = 'green';
          status.jobs.forEach(function(job, idx) {
              v_log('hudson: job:' + JSON.stringify(job));
              var job_status = job.color.split('_', 2);
              if(job_status[0] == 'red') { color = 'red'; }
              if(job_status[1] == 'anime') { building = true; }
            });
          sendCommand(config.hudsonCommand(color, building) + ';');
          v_log('hudson: color=' + color + ', building=' + building);
        });
    });

  request.end();
}

sendCommand(config.heartStopCommand() + ';' + config.initCommand() + ';');

setInterval(function() {
  checkHudson();
}, config.updateInterval());
