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
local urlparams = --require "net.http".getQueryParams or whatever MattJ names it
function(s)
	if not s:match("=") then return urldecode(s); end
	local r = {}
	s:gsub("([^=&]*)=([^&]*)", function(k,v)
		r[ urldecode(k) ] = urldecode(v);
		return nil
	end)
	return r
end;

--COMPAT 0.7
if not test_password then
	local validate_credentials = require "core.usermanager".validate_credentials;
	test_password = function(user, host, password)
		return validate_credentials(host, user, password)
	end
end

local function http_response(code, message, extra_headers)
	local response = {
		status = code .. " " .. message;
		body = message .. "\n"; }
	if extra_headers then response.headers = extra_headers; end
	return response
end

local function handle_request(method, body, request)
	if request.method == "BREW" then return http_response(418, "I'm a teapot"); end
	if request.method ~= "POST" then
		return http_response(405, "Method Not Allowed", {["Allow"] = "POST"}); end

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
			:match("[^ ]*$") or ""):match("([^:]*):(.*)");
	from_jid = jid_prep(from_jid)
	if not from_jid or not password then return http_response(400, "Bad Request"); end
	local from_user, from_host = jid_split(from_jid)
	if not hosts[from_host] then return http_response(401, "Unauthorized"); end

	-- auth
	module:log("debug", "testing authz %s", from_jid)
	if not test_password(from_user, from_host, password) then
		return http_response(401, "Unauthorized")
	end

	-- parse body
	local message = {}
	local body_type = request.headers["content-type"]
	if body_type == "text/plain" then
		message = {["body"] = body}
	elseif body_type == "application/x-www-form-urlencoded" then
		message = urlparams(body)
		if type(message) == "string" then
			message = {["body"] = message}
		end
	else
		return http_response(415, "Unsupported Media Type")
	end

	-- guess type if not set
	if not message["type"] then
		if message["body"] then 
			if message["subject"] then
				message["type"] = "normal"
			else
				message["type"] = "chat"
			end
		elseif not message["body"] and message["subject"] then
			message["type"] = "headline"
		end
	end

	-- build stanza
	local stanza = msg({["to"]=to_jid, ["from"]=from_jid, ["type"]=message["type"]})
	if message["body"] then stanza:tag("body"):text(message["body"]):up(); end
	if message["subject"] then stanza:tag("subject"):text(message["subject"]):up(); end

	-- and finaly post it
	module:log("debug", "message for %s", to_jid)
	core_post_stanza(hosts[module.host], stanza)
	return http_response(202, "Accepted")
end

local function setup()
	local ports = module:get_option("post_msg_ports") or { 5280 };
	require "net.httpserver".new_from_config(ports, handle_request, { base = "msg" });
end
if prosody.start_time then -- already started
	setup();
else
	prosody.events.add_handler("server-started", setup);
end
