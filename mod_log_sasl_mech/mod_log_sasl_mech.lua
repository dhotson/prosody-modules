
module:hook("authentication-success", function (event)
	local session = event.session;
	local sasl_handler = session.sasl_handler;
	session.log("info", "Authenticated with %s", sasl_handler and sasl_handler.selected or "legacy auth");
end);
