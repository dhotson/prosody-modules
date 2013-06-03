local datamanager = require "util.datamanager";	
local time = os.time;
local log_ip = module:get_option_boolean("lastlog_ip_address", false);
local host = module.host;

module:hook("authentication-success", function(event)
	local session = event.session;
	if session.username then
		datamanager.store(session.username, host, "lastlog", {
			event = "login";
			timestamp = time(),
			ip = log_ip and session.ip or nil,
		});
	end
end);

module:hook("resource-unbind", function(event)
	local session = event.session;
	if session.username then
		datamanager.store(session.username, host, "lastlog", {
			event = "logout";
			timestamp = time(),
			ip = log_ip and session.ip or nil,
		});
	end
end);

function module.command(arg)
	local user, host = require "util.jid".prepped_split(table.remove(arg, 1));
	local lastlog = datamanager.load(user, host, "lastlog") or {};
	print("Last login: "..(lastlog and os.date("%Y-%m-%d %H:%m:%s", datamanager.load(user, host, "lastlog").time) or "<unknown>"));
	if lastlog.ip then
		print("IP address: "..lastlog.ip);
	end
	return 0;
end
