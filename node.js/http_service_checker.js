"use strict";

var http = require('http'),
    url  = require('url'),
    util = require('util'),
    logger = require('./logger'),
    service_checker = require('./service_checker');

function HttpChecker(config) {
  var self = this;
  service_checker.ServiceChecker.call(this, config);

  var pendingCallback = null;

  var service_url = url.parse(config.url);

  var method = config.method || 'GET';
  var secure = service_url.protocol == 'https:';
  var host   = service_url.hostname;
  var port   = service_url.port || 80;
  var path   = service_url.pathname;
  var auth   = service_url.auth ?
    'Basic ' + new Buffer(service_url.auth).toString('base64') :
    undefined;

  var headers = { 'Host' : host };
  if(auth) { headers.Authorization = auth; }

  self.createClient = function () {
    self.client = http.createClient(port, host, secure);
    self.client.on('error', function(exception) {
        self.client = undefined;
        if(pendingCallback) { pendingCallback(); }
      });
  };

  this.createRequest = function(errorCallback) {
    try {
      if(!self.client) { self.createClient(); }
      pendingCallback = errorCallback;
      return self.client.request(method, path, headers);
    } catch(exception) {
      console.log('Caught an exception: ' + exception.message + exception.stack);
      errorCallback();
    }
  };
}
util.inherits(HttpChecker, service_checker.ServiceChecker);

HttpChecker.prototype.check = function(callback) {
  var self = this;
  var request;

  try {
    request = self.createRequest(function() {
      self.serviceDownCommand(callback);
    });

    request.on('response', function(response) {
        var data = '';
        response.on('data', function(chunk) { data += chunk; });
        response.on('end', function() {
            self.serviceUpCommand(callback, request, response, data);
          });
      });

    request.end();
  } catch(exception) {
    console.log('Caught an exception: ' + exception.message + exception.stack);
    self.serviceDownCommand(callback);
  }
};

HttpChecker.prototype.serviceUpCommand = function(callback, request, response, data) {};
HttpChecker.prototype.serviceDownCommand = function(callback) {};

exports.HttpChecker = HttpChecker;
