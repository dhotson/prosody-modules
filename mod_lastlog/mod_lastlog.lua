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
	require"core.storagemanager".initialize_host(host);
	local lastlog = assert(datamanager.load(user, host, "lastlog"));
	if lastlog then
		print(("Last %s: %s"):format(lastlog.event or "login",
		lastlog.timestamp and os.date("%Y-%m-%d %H:%M:%S", lastlog.timestamp) or "<unknown>"));
		if lastlog.ip then
			print("IP address: "..lastlog.ip);
		end
	else
		print("No record found");
	end
	return 0;
end
