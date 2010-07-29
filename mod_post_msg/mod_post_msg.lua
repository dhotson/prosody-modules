-- Recive a HTTP POST and relay it
-- By Kim Alvefur <zash@zash.se>
-- Some code borrowed from mod_webpresence
--
-- Example usage:
--     curl http://example.com:5280/msg/user -u me@example.com:mypassword -d "Hello there"
-- This would send a message to user@example.com from me@example.com


local jid_split = require "util.jid".split;
local jid_prep = require "util.jid".prep;
local msg = require "util.stanza".message;
local test_password = require "core.usermanager".test_password;
local b64_decode = require "util.encodings".base64.decode;
local urldecode = require "net.http".urldecode;

local function http_response(code, message, extra_headers)
	local response = {
		status = code .. " " .. message;
		body = message .. "\n"; }
	if extra_headers then response.headers = extra_headers; end
	return response
end

local function handle_request(method, body, request)
	if request.method ~= "POST" then return http_response(405, "Method Not Allowed"); end

	-- message to?
	local path_jid = request.url.path:match("[^/]+$");
	if not path_jid or not body then return http_response(400, "Bad Request"); end
	local to_user, to_host = jid_split(urldecode(path_jid));
	if to_host and not to_user and request.headers.host then
		to_user, to_host = to_host, request.headers.host;
		if to_host then to_host = to_host:gsub(":%d+$", ""); end
	end
	if not to_host or not to_user then return http_response(400, "Bad Request"); end 
	local to_jid = jid_prep(to_user .. "@" .. to_host)
	if not to_jid then return http_response(400, "Bad Request"); end 

	-- message from?
	if not request.headers["authorization"] then
		return http_response(401, "Unauthorized",
			{["WWW-Authenticate"]='Basic realm="WallyWorld"'})
	end
	local from_jid, password = b64_decode(request.headers.authorization
			:gmatch("[^ ]*$")() or ""):gmatch("([^:]*):(.*)")();
	from_jid = jid_prep(from_jid)
	if not from_jid or not password then return http_response(400, "Bad Request"); end
	local from_user, from_host = jid_split(from_jid)
	if not hosts[from_host] then return http_response(401, "Unauthorized"); end

	-- auth
	module:log("debug", "testing authz %s", from_jid)
	if not test_password(from_user, from_host, password) then
		return http_response(401, "Unauthorized"); end

	module:log("debug", "message for %s", to_jid)
	core_post_stanza(hosts[module.host], msg({to=to_jid, from=from_jid, type="chat"})
			:tag("body"):text(body))
	return http_response(202, "Accepted")
end

local ports = config.get(module.host, "core", "post_msg_ports") or { 5280 };
require "net.httpserver".new_from_config(ports, "msg", handle_request);
