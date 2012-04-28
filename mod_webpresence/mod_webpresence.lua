module:depends("http");

local jid_split = require "util.jid".prepped_split;

if not require_resource then
	function require_resource(name)
		local icon_path = module:get_option_string("presence_icons", "icons");
		local f, err  = module:load_resource(icon_path.."/"..name);
		if f then
			return f:read("*a");
		end
		module:log("warn", "Failed to open image file %s", icon_path..name);
		return "";
	end
end

local statuses = { "online", "away", "xa", "dnd", "chat", "offline" };

for _, status in ipairs(statuses) do
	statuses[status] = { status_code = 200, headers = { content_type = "image/png" }, 
		body = require_resource("status_"..status..".png") };
end

local function handle_request(event, path)
	local jid = path:match("[^/]+$");
	if jid then
		local user, host = jid_split(jid);
		if host and not user then
			user, host = host, event.request.headers.host;
			if host then host = host:gsub(":%d+$", ""); end
		end
		if user and host then
			local user_sessions = hosts[host] and hosts[host].sessions[user];
			if user_sessions then
				local status = user_sessions.top_resources[1];
				if status and status.presence then
					status = status.presence:child_with_name("show");
					if not status then
						status = "online";
					else
						status = status:get_text();
					end
					return statuses[status];
				end
			end
		end
	end
	return statuses.offline;
end

module:provides("http", {
	default_path = "/status";
	route = {
		["GET /*"] = handle_request;
	};
});
