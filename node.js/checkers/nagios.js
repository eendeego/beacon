/**
 * Check Nagios state through nagiosity.js.
 * (https://github.com/luismreis/nagiosity.js)
 *
 * Can ignore or only pay attention to a set of hosts / services
 * via except/only configuration options.
 */

"use strict";

var util = require('util'),
    logger = require('../logger'),
    service_checker = require('../service_checker'),
    http_checker = require('../http_service_checker');


function hostToMap(type, str) {
  var map = {};
  map[str] = type == 'only' ? 'all' : [];
  return map;
}

function hostArrayToMap(type, array) {
  var services = type == 'only' ? 'all' : [];
  return array.reduce(function(map, elt) { map[elt] = services; return map; }, {});
}

function servicesToMap(services) {
  if(typeof services == 'string') {
    services = [services];
  }
  return services.reduce(function(map, elt) { map[elt] = 1; return map; }, {});
}

// http://www.hunlock.com/blogs/Ten_Javascript_Tools_Everyone_Should_Have
function isArray(testObject) {
  return testObject &&
    !(testObject.propertyIsEnumerable('length')) &&
    typeof testObject === 'object' &&
    typeof testObject.length === 'number';
}

function getRules(type, src) {
  if(typeof src == 'string') {
    return hostToMap(type, src);
  } else
  if(isArray(src)) {
    return hostArrayToMap(type, src);
  } else {
    return Object.keys(src).reduce(function(map, host) {
      map[host] = servicesToMap(src[host]); return map;
    }, {});
  }
}

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

  this.checkService = function(host, service, highestState) {
    return Math.max(highestState, service.current_state);
  };

  this.checkAnyHost = function(host, highestState) {
    highestState = Math.max(highestState, host.current_state);
    return host.services.reduce(function(state, service) {
        return self.checkService(host, service, state);
      }, highestState);
  };

  var checkOnlyHost = function(host, highestState) {
    var onlyServices = self.onlyHosts[host.host_name];

    if(!onlyServices) { return highestState; }
    if(onlyServices == 'all') { return self.checkAnyHost(host, highestState); }

    highestState = Math.max(highestState, host.current_state);
    return host.services.reduce(function(state, service) {
        return service.service_description in onlyServices ?
          self.checkService(host, service, state) :
          state;
      }, highestState);
  };

  var checkExceptHost = function(host, highestState) {
    var exceptServices = self.exceptHosts[host.host_name];

    if(!exceptServices) { return self.checkAnyHost(host, highestState); }
    if(exceptServices == []) { return highestState; }

    highestState = Math.max(highestState, host.current_state);
    return host.services.reduce(function(state, service) {
        return service.service_description in exceptServices ?
          highestState :
          self.checkService(host, service, state);
      }, highestState);
  };

  if('only' in config) {
    if('except' in config) { throw new Exception("Can't use only and except hosts at the same time."); }

    this.onlyHosts = getRules('only', config.only);
    this.checkHost = checkOnlyHost;
  } else if('except' in config) {
    this.exceptHosts = getRules('except', config.except);
    this.checkHost = checkExceptHost;
  } else {
    this.checkHost = this.checkAnyHost;
  }

  this.state = function(stateNumber) { return states[stateNumber]; };
}
util.inherits(NagiosChecker, http_checker.HttpChecker);

NagiosChecker.prototype.serviceUpCommand = function(callback, request, response, data) {
  var self = this;

  var highestState = JSON.parse(data).hosts.reduce(function(state, host) {
    return self.checkHost(host, state);
  }, 0);

  logger.log('nagios: state=' + self.state(highestState));
  callback(self.nagiosUpCommand(self.state(highestState)));
};

NagiosChecker.prototype.serviceDownCommand = function(callback) {
  callback(this.nagiosDownCommand());
};

service_checker.registerChecker('nagios', NagiosChecker);
