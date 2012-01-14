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

local set_realm_name = module:get_option("reg_servlet_realm") or "Restricted"
local throttle_time = module:get_option("reg_servlet_ttime") or false
local whitelist = module:get_option("reg_servlet_wl") or {}
local blacklist = module:get_option("reg_servlet_bl") or {}
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
			if blacklist[req_body["ip"]] then module:log("warn", "Attempt of reg. submission to the JSON servlet from blacklisted address: %s", req_body["ip"]) ; return http_response(403, "The specified address is blacklisted, sorry sorry.") end
			if throttle_time and not whitelist[req_body["ip"]] then
				if not recent_ips[req_body["ip"]] then
					recent_ips[req_body["ip"]] = { time = os_time(), count = 1 }
				else
					local ip = recent_ips[req_body["ip"]]
					ip.count = ip.count + 1

					if os_time() - ip.time < throttle_time then
						ip.time = os_time()
						module:log("warn", "JSON Registration request from %s has been throttled.", req_body["ip"])
						return http_response(503, "Woah... How many users you want to register..? Request throttled, wait a bit and try again.")
					end
					ip.time = os_time()
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
					usermanager.create_user(username, req_body["password"], req_body["host"])
					module:log("debug", "%s registration data submission for %s is successful", user, username)
					return http_response(200, "Done.")
				end
			else
				module:log("debug", "%s registration data submission for %s failed (user already exists)", user, username)
				return http_response(409, "User already exists.")
			end
		end
	end
end

-- Set it up!
local function setup()
	local ports = module:get_option("reg_servlet_ports") or { 9280 }
	local port_number, base_name, ssl_table
	for _, opts in ipairs(ports) do
		if type(opts) == "number" then
			port_number, base_name = opts, "register_account"
		elseif type(opts) == "table" then
			port_number, base_name, ssl_table = opts.port or 9280, opts.path or "register_account", opts.ssl or nil
		elseif type(opts) == "string" then
			base_name, port_number = opts, 9280
		end
	end
	
	if ssl_table == nil then
		ports = { { port = port_number } }
		httpserver.new_from_config(ports, handle_req, { base = base_name })
	else
		if port_number == 9280 then port_number = 9443 end
		ports = { { port = port_number, ssl = ssl_table } }
		httpserver.new_from_config(ports, handle_req, { base = base_name })
	end
end

if prosody.start_time then -- already started
	setup()
else
	module:hook("server-started", setup)
end
