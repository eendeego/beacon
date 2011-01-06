"use strict";

var util = require('util'),
    logger = require('../logger'),
    service_checker = require('../service_checker'),
    http_checker = require('../http_service_checker');

function HudsonChecker(config) {
  var self = this;
  http_checker.HttpChecker.call(this, config);

  this.hudsonUpCommand = config.hudsonUpCommand ||
    function(color, building) {
      return 'bm(12).' + (color == 'green' ? 'g' : 'r') + '.w' +
        (building ? '.b(2).a' : '');
    };

  this.hudsonDownCommand = config.hudsonDownCommand ||
    function() {
      return 'bm(12).b.p';
    };
}
util.inherits(HudsonChecker, http_checker.HttpChecker);

HudsonChecker.prototype.serviceUpCommand = function(callback, request, response, data) {
  var self = this;

  var building = false;
  var color = 'green';
  JSON.parse(data).jobs.forEach(function(job, idx) {
      logger.log('hudson: job:' + JSON.stringify(job));
      var job_status = job.color.split('_', 2);
      if(job_status[0] == 'red') { color = 'red'; }
      if(job_status[1] == 'anime') { building = true; }
    });
  logger.log('hudson: color=' + color + ', building=' + building);
  callback(self.hudsonUpCommand(color, building));
};

HudsonChecker.prototype.serviceDownCommand = function(callback) {
  callback(this.hudsonDownCommand());
};

service_checker.registerChecker('hudson', HudsonChecker);
