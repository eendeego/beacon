"use strict";

var util = require('util'),
    logger = require('../logger'),
    service_checker = require('../service_checker'),
    http_checker = require('../http_service_checker');

function NagiosChecker(config) {
  var self = this;
  http_checker.HttpChecker.call(this, config);

  var states = ['ok', 'warning', 'critical', 'unknown'];
  var stateColors = { ok: 'g', warning: 'h(15)', critical: 'r', unknown: 'h(300)'};

  this.nagiosUpCommand = config.nagiosUpCommand ||
    function(state) {
      return 'bm(3).' + stateColors[state] + '.w';
    };

  this.nagiosDownCommand = config.nagiosDownCommand ||
    function() {
      return 'bm(3).b.p';
    };

  this.state = function(stateNumber) { return states[stateNumber]; };
}
util.inherits(NagiosChecker, http_checker.HttpChecker);

NagiosChecker.prototype.serviceUpCommand = function(callback, request, response, data) {
  var self = this;

  var highestState = 0;
  JSON.parse(data).hosts.forEach(function(host) {
    // test for only/except
    highestState = Math.max(highestState, host.current_state);
    host.services.forEach(function(service) {
      // test for only/except
      highestState = Math.max(highestState, service.current_state);
    });
  });

  logger.log('nagios: state=' + self.state(highestState));
  callback(self.nagiosUpCommand(self.state(highestState)));
};

NagiosChecker.prototype.serviceDownCommand = function(callback) {
  callback(this.nagiosDownCommand());
};

service_checker.registerChecker('nagios', NagiosChecker);
