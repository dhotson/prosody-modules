-- Expose a simple servlet to handle user registrations from web pages
-- via JSON.
--
-- A Good chunk of the code is from mod_data_access.lua by Kim Alvefur
-- aka Zash.

local jid_prep = require "util.jid".prep
local jid_split = require "util.jid".split
local usermanager = require "core.usermanager"
local b64_decode = require "util.encodings".base64.decode
local json_decode = require "util.json".decode
local httpserver = require "net.httpserver"
local os_time = os.time
local nodeprep = require "util.encodings".stringprep.nodeprep

module.host = "*" -- HTTP/BOSH Servlets need to be global.

-- Pick up configuration.

local set_realm_name = module:get_option_string("reg_servlet_realm", "Restricted")
local throttle_time = module:get_option_number("reg_servlet_ttime", nil)
local whitelist = module:get_option_set("reg_servlet_wl", {})
local blacklist = module:get_option_set("reg_servlet_bl", {})
local ports = module:get_option_array("reg_servlet_ports", {{ port = 9280 }})
local recent_ips = {}

-- Begin

local function http_response(code, message, extra_headers)
        local response = {
                status = code .. " " .. message,
                body = message .. "\n" }
        if extra_headers then response.headers = extra_headers end
        return response
end

local function handle_req(method, body, request)
	if request.method ~= "POST" then
		return http_response(405, "Bad method...", {["Allow"] = "POST"})
	end
	if not request.headers["authorization"] then
		return http_response(401, "No... No...", {["WWW-Authenticate"]='Basic realm="'.. set_realm_name ..'"'})
	end
	
	local user, password = b64_decode(request.headers.authorization:match("[^ ]*$") or ""):match("([^:]*):(.*)")
	user = jid_prep(user)
	if not user or not password then return http_response(400, "What's this..?") end
	local user_node, user_host = jid_split(user)
	if not hosts[user_host] then return http_response(401, "Negative.") end
	
	module:log("warn", "%s is authing to submit a new user registration data", user)
	if not usermanager.test_password(user_node, user_host, password) then
		module:log("warn", "%s failed authentication", user)
		return http_response(401, "Who the hell are you?! Guards!")
	end
	
	local req_body
	-- We check that what we have is valid JSON wise else we throw an error...
	if not pcall(function() req_body = json_decode(body) end) then
		module:log("debug", "JSON data submitted for user registration by %s failed to Decode.", user)
		return http_response(400, "JSON Decoding failed.")
	else
		-- Decode JSON data and check that all bits are there else throw an error
		req_body = json_decode(body)
		if req_body["username"] == nil or req_body["password"] == nil or req_body["host"] == nil or req_body["ip"] == nil then
			module:log("debug", "%s supplied an insufficent number of elements or wrong elements for the JSON registration", user)
			return http_response(400, "Invalid syntax.")
		end
		-- Check if user is an admin of said host
		if not usermanager.is_admin(user, req_body["host"]) then
			module:log("warn", "%s tried to submit registration data for %s but he's not an admin", user, req_body["host"])
			return http_response(401, "I obey only to my masters... Have a nice day.")
		else	
			-- Checks for both Throttling/Whitelist and Blacklist (basically copycatted from prosody's register.lua code)
			if blacklist:contains(req_body["ip"]) then module:log("warn", "Attempt of reg. submission to the JSON servlet from blacklisted address: %s", req_body["ip"]) ; return http_response(403, "The specified address is blacklisted, sorry sorry.") end
			if throttle_time and not whitelist:contains(req_body["ip"]) then
				if not recent_ips[req_body["ip"]] then
					recent_ips[req_body["ip"]] = os_time()
				else
					if os_time() - recent_ips[req_body["ip"]] < throttle_time then
						recent_ips[req_body["ip"]] = os_time()
						module:log("warn", "JSON Registration request from %s has been throttled.", req_body["ip"])
						return http_response(503, "Woah... How many users you want to register..? Request throttled, wait a bit and try again.")
					end
					recent_ips[req_body["ip"]] = os_time()
				end
			end

			-- We first check if the supplied username for registration is already there.
			-- And nodeprep the username
			local username = nodeprep(req_body["username"])
			if not usermanager.user_exists(username, req_body["host"]) then
				if not username then
					module:log("debug", "%s supplied an username containing invalid characters: %s", user, username)
					return http_response(406, "Supplied username contains invalid characters, see RFC 6122.")
				else
					local ok, error = usermanager.create_user(username, req_body["password"], req_body["host"])
					if ok then 
						hosts[req_body["host"]].events.fire_event("user-registered", { username = username, host = req_body["host"], source = "mod_register_json", session = { ip = req_body["ip"] } })
						module:log("debug", "%s registration data submission for %s@%s is successful", user, username, req_body["host"])
						return http_response(200, "Done.")
					else
						module:log("error", "user creation failed: "..error)
						return http_response(500, "Encountered server error while creating the user: "..error)
					end
				end
			else
				module:log("debug", "%s registration data submission for %s failed (user already exists)", user, username)
				return http_response(409, "User already exists.")
			end
		end
	end
end

-- Set it up!
function regj_cleanup() -- it could be better if module:hook("module-unloaded", ...) actually worked.
	module:log("debug", "Cleaning up handlers and stuff as module is being unloaded.")
	for _, options in ipairs(ports) do
		if options.port then
			httpserver.new.http_servers[options.port].handlers[options.path or "register_account"] = nil
		end
	end

	-- if there are no handlers left clean and close the socket, doesn't work with server_event
	local event = require "core.configmanager".get("*", "core", "use_libevent");

	if not event then
		for _, options in ipairs(ports) do
			if options.port and not next(httpserver.new.http_servers[options.port].handlers) then
				httpserver.new.http_servers[options.port] = nil
				if options.interface then
					for _, value in ipairs(options.interface) do
						if server.getserver(value, options.port) then server.removeserver(value, options.port) end
					end
				else if server.getserver("*", options.port) then server.removeserver("*", options.port) end end
			end
		end
	end

	prosody.events.remove_handler("module-unloaded", regj_cleanup)
end

function setup()
	for id, options in ipairs(ports) do 
		if not options.port then 
			if not options.ssl then ports[id].port = 9280
			else ports[id].port = 9443 end
		elseif options.port == 9280 and options.ssl then ports[id].port = 9443 end end
	httpserver.new_from_config(ports, handle_req, { base = "register_account" })
	prosody.events.add_handler("module-unloaded", regj_cleanup)
end

if prosody.start_time then -- already started
	setup()
else
	module:hook("server-started", setup)
end
