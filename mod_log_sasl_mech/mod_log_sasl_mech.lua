
module:hook("authentication-success", function (event)
	local sasl_handler = event.session.sasl_handler;
	module:log("info", "Authenticated with %s", sasl_handler and sasl_handler.selected or "legacy auth");
end);
