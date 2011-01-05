"use strict";

function ServiceChecker(configuration) {
  var config = configuration;

  this.config = function() {
    return config;
  };
}
ServiceChecker.prototype.check = function(callback) {};

exports.ServiceChecker = ServiceChecker;

var services = {};

module.exports.registerChecker = function(name, checker) {
  services[name] = checker;
}

module.exports.getChecker = function(name) {
  return services[name];
}
