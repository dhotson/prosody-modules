local datamanager = require "util.datamanager";	
local time = os.time;
local log_ip = module:get_option_boolean("lastlog_ip_address", false);

module:hook("authentication-success", function(event)
	local session = event.session;
	if session.username then
		datamanager.store(session.username, session.host, "lastlog", {
			timestamp = time(),
			ip = log_ip and session.ip or nil,
		});
	end
end);
