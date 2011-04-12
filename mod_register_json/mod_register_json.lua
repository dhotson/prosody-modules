-- Expose a simple servlet to handle user registrations from web pages
-- via JSON.
--
-- A Good chunk of the code is from mod_data_access.lua by Kim Alvefur
-- aka Zash.

local usermanager = require "core.usermanager";
local b64_decode = require "util.encodings".base64.decode;
local json_decode = require "util.json".decode;

module.host = "*" -- HTTP/BOSH Servlets need to be global.

local set_realm_name = module:get_option("reg_servlet_realm") or "Restricted";

local function http_response(code, message, extra_headers)
        local response = {
                status = code .. " " .. message;
                body = message .. "\n"; }
        if extra_headers then response.headers = extra_headers; end
        return response
end

local function handle_req(method, body, request)
	if request.method ~= "POST" then
		return http_response(405, "Bad method...", {["Allow"] = "POST"});
	end
	if not request.headers["authorization"] then
		return http_response(401, "No... No...",
		{["WWW-Authenticate"]='Basic realm="'.. set_realm_name ..'"'})
	end
	
	local user, password = b64_decode(request.headers.authorization
		:match("[^ ]*$") or ""):match("([^:]*):(.*)");
	user = jid_prep(user);
	if not user or not password then return http_response(400, "What's this..?"); end
	local user_node, user_host = jid_split(user)
	if not hosts[user_host] then return http_response(401, "Negative."); end
	
	module:log("debug", "%s is authing to submit a new user registration data", user)
	if not usermanager.test_password(user_node, user_host, password) then
		module:log("debug", "%s failed authentication", user)
		return http_response(401, "Who the hell are you?! Guards!");
	end
	
	local req_body; pcall(function() req_body = json.decode(body) end);
	-- Check if user is an admin of said host
	if not usermanager.is_admin(user, req_body["host"]) then
		module:log("debug", "%s tried to submit registration data for %s but he's not an admin", user, req_body["host"])
		return http_response(401, "I obey only to my masters... Have a nice day.");
	else
		-- Various sanity checks.
		if req_body == nil then module:log("debug", "JSON data submitted for user registration by %s failed to Decode.", user); return http_response(400, "JSON Decoding failed."); end
		-- We first check if the supplied username for registration is already there.
		if not usermanager.user_exists(req_body["username"], req_body["host"]) then
			usermanager.create_user(req_body["username"], req_body["password"], req_body["host]);
			module:log("debug", "%s registration data submission for %s is successful", user, req_body["user"]);
			return http_response(200, "Done.");
		else
			module:log("debug", "%s registration data submission for %s failed (user already exists)", user, req_body["user"]);
			return http_response(409, "User already exists.");
		end
	end
end

local function setup()
        local ports = module:get_option("reg_servlet_port") or { 9443 };
        local base_name = module:get_option("reg_servlet_base") or "register_account";
        local ssl_cert = module:get_option("reg_servlet_sslcert") or false;
        local ssl_key = module:get_option("reg_servlet_sslkey") or false;
        if not ssl_cert or not ssl_key then
        	require "net.httpserver".new_from_config(ports, handle_req, { base = base_name });
        else
        	require "net.httpserver".new_from_config(ports, handle_req, { ssl = { key = ssl_key, certificate = ssl_cert }, base = base_name });
	end
end
if prosody.start_time then -- already started
        setup();
else
        prosody.events.add_handler("server-started", setup);
end
