module:depends("http");

local jid_split = require "util.jid".prepped_split;
local b64 = require "util.encodings".base64.encode;
local sha1 = require "util.hashes".sha1;

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
--[[for status, _ in pairs(statuses) do
	statuses[status].image = { status_code = 200, headers = { content_type = "image/png" },
		body = require_resource("status_"..status..".png") };
	statuses[status].text = { status_code = 200, headers = { content_type = "text/plain" },
		body = status };
end]]

local function handle_request(event, path)
	local status, message;
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
					message = status.presence:child_with_name("status");
					status = status.presence:child_with_name("show");
					if not status then
						status = "online";
					else
						status = status:get_text();
					end
					if message then
						message = message:get_text();
					end
				end
			end
		end
	end
	status = status or "offline";
	if type == "" then type = "image" end;
	if type == "image" then 
		statuses[status].image = { status_code = 200, headers = { content_type = "image/png" }, 
			body = require_resource("status_"..status..".png") };
	elseif type == "html" then
		local jid_hash = sha1(jid, true);
		statuses[status].html = { status_code = 200, headers = { content_type = "text/html" },
			body = [[<div id="]]..jid_hash..[[_status" class="xmpp_status">]]..
					[[<img id="]]..jid_hash..[[_img" class="xmpp_status_image" ]]..
						[[src="data:image/png;base64,]]..
						b64(require_resource("status_"..status..".png"))..[[">]]..
					[[<span id="]]..jid_hash..[[_name" ]]..
						[[class="xmpp_status_name">]]..status..[[</span>]]..
					(message and [[<span id="]]..jid_hash..[[_message" ]]..
						[[class="xmpp_status_message">]]..message..[[</span>]] or "")..
				[[</div>]] };
	elseif type == "text" then
		statuses[status].text = { status_code = 200, headers = { content_type = "text/plain" },
			body = status };
	elseif type == "message" then
		statuses[status].message = { status_code = 200, headers = { content_type = "text/plain" },
			body = (message and message or "") };
	end
	return statuses[status][type];
end

module:provides("http", {
	default_path = "/status";
	route = {
		["GET /*"] = handle_request;
	};
});
