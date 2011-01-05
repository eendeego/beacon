"use strict;"

// This is no log4j, keeping it simple (as much as possible)

function iso8601date() {
  var date = new Date();

  function pad(number) {
    return (number < 10 ? '0' : '') + number;
  }
  function pad3(number) {
    return (number < 10 ? '0' : (number < 100 ? '00' : '')) + number;
  }

  return date.getUTCFullYear() + '-' +
    pad(date.getUTCMonth() + 1) + '-' +
    pad(date.getUTCDay()) + ' ' +
    pad(date.getUTCHours()) + ':' +
    pad(date.getUTCMinutes()) + ':' +
    pad(date.getUTCSeconds()) + '.' +
    pad3(date.getUTCMilliseconds());
}

function enabledLogger(message) {
  console.log(iso8601date() + ' ' + message);
}

function disabledLogger(message) {
  // no op
}

var logger = disabledLogger;

module.exports.log = function(message) {
  logger(message);
}

module.exports.enableLogging = function() {
  logger = enabledLogger;
}

module.exports.disableLogging = function() {
  logger = disabledLogger;
}
