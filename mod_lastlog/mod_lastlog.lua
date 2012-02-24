local datamanager = require "util.datamanager";	
local time = os.time;

module:hook("authentication-success", function(event)
	local session = event.session;
	if session.username then
		datamanager.store(session.username, session.host, "lastlog", {
			timestamp = time(),
		});
	end
end);
