"use strict";

var http = require('http'),
    url  = require('url'),
    util = require('util'),
    logger = require('../logger'),
    service_checker = require('../service_checker');

function HudsonChecker(config) {
  var self = this;
  service_checker.ServiceChecker.call(this, config);

  var pendingCallback = null;

  this.hudsonCommand = config.hudsonCommand ||
    function(color, building) {
      return 'bm(15).' + (color == 'green' ? 'g' : 'r') + '.w' +
        (building ? '.bm(3).a' : '');
    };

  this.hudsonDownCommand = config.hudsonDownCommand ||
    function() {
      return 'bm(15).b.p';
    }

  var hudson_url = url.parse(config.url);

  var host   = hudson_url.hostname;
  var port   = hudson_url.port || 80;
  var secure = hudson_url.protocol == 'https:';
  var auth   = hudson_url.auth ?
    'Basic ' + new Buffer(hudson_url.auth).toString('base64') :
    undefined;

  function createClient() {
    self.hudson = http.createClient(port, host, secure);
    self.hudson.on('error', function(exception) {
        self.hudson = undefined;
        if(pendingCallback) { pendingCallback(); }
      });
  }

  var request_headers = { 'Host' : host };
  if(auth) { request_headers.Authorization = auth; }

  this.createRequest = function(errorCallback) {
    try {
      if(!self.hudson) { createClient(); }
      pendingCallback = errorCallback;
      return self.hudson.request('GET', '/api/json', request_headers);
    } catch(exception) {
      errorCallback();
    }
  };
}
util.inherits(HudsonChecker, service_checker.ServiceChecker);

HudsonChecker.prototype.check = function(callback) {
  var self = this;
  var request;

  try {
    request = this.createRequest(function() {
      callback(self.hudsonDownCommand());
    });

    request.on('response', function(response) {
        var result = '';
        response.on('data', function(chunk) { result += chunk; });
        response.on('end', function() {
            var building = false;
            var color = 'green';
            JSON.parse(result).jobs.forEach(function(job, idx) {
                logger.log('hudson: job:' + JSON.stringify(job));
                var job_status = job.color.split('_', 2);
                if(job_status[0] == 'red') { color = 'red'; }
                if(job_status[1] == 'anime') { building = true; }
              });
            logger.log('hudson: color=' + color + ', building=' + building);
            callback(self.hudsonCommand(color, building));
          });
      });

    request.end();
  } catch(exception) {
    console.log('Caught an exception: ' + exception.message + exception.stack);
    callback(self.hudsonDownCommand());
  }
};

service_checker.registerChecker('hudson', HudsonChecker);
