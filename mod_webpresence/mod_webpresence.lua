module:depends("http");

local jid_split = require "util.jid".prepped_split;

local function require_resource(name)
	local icon_path = module:get_option_string("presence_icons", "icons");
	local f, err  = module:load_resource(icon_path.."/"..name);
	if f then
		return f:read("*a");
	end
	module:log("warn", "Failed to open image file %s", icon_path..name);
	return "";
end

local statuses = { online = {}, away = {}, xa = {}, dnd = {}, chat = {}, offline = {} };

for status, _ in pairs(statuses) do
	statuses[status].image = { status_code = 200, headers = { content_type = "image/png" }, 
		body = require_resource("status_"..status..".png") };
	statuses[status].text = { status_code = 200, headers = { content_type = "plain/text" },
		body = status };
end

local function handle_request(event, path)
	local status;
	local jid, type = path:match("([^/]+)/?(.*)$");
	if jid then
		local user, host = jid_split(jid);
		if host and not user then
			user, host = host, event.request.headers.host;
			if host then host = host:gsub(":%d+$", ""); end
		end
		if user and host then
			local user_sessions = hosts[host] and hosts[host].sessions[user];
			if user_sessions then
				status = user_sessions.top_resources[1];
				if status and status.presence then
					status = status.presence:child_with_name("show");
					if not status then
						status = "online";
					else
						status = status:get_text();
					end
				end
			end
		end
	end

	status = status or "offline";
	return (type and type == "text") and statuses[status].text or statuses[status].image;
end

module:provides("http", {
	default_path = "/status";
	route = {
		["GET /*"] = handle_request;
	};
});
