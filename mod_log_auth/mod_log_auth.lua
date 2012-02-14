
module:hook("authentication-failure", function (event)
	module:log("info", "Failed authentication attempt (%s) from IP: %s", event.condition, event.session.ip);
end);
