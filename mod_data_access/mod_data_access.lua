-- HTTP Access to datamanager
-- By Kim Alvefur <zash@zash.se>

local jid_prep = require "util.jid".prep;
local jid_split = require "util.jid".split;
local um_test_pw = require "core.usermanager".test_password;
local is_admin = require "core.usermanager".is_admin
local dm_load = require "util.datamanager".load;
local dm_list_load = require "util.datamanager".list_load;
local b64_decode = require "util.encodings".base64.decode;
--local urldecode = require "net.http".urldecode;
--[[local urlparams = --require "net.http".getQueryParams or whatever MattJ names it
function(s)
	if not s:match("=") then return urldecode(s); end
	local r = {}
	s:gsub("([^=&]*)=([^&]*)", function(k,v)
		r[ urldecode(k) ] = urldecode(v);
		return nil
	end)
	return r
end;
--]]

local function http_response(code, message, extra_headers)
	local response = {
		status = code .. " " .. message;
		body = message .. "\n"; }
	if extra_headers then response.headers = extra_headers; end
	return response
end

local encoders = {
	lua = require "util.serialization".serialize,
	json = require "util.json".encode
};
--[[
encoders.xml = function(data)
	return "<?xml version='1.0' encoding='utf-8'?><todo:write-this-serializer/>";
end --]]

local function handle_request(method, body, request)
	if request.method ~= "GET" then
		return http_response(405, "Method Not Allowed", {["Allow"] = "GET"});
	end -- TODO Maybe PUT?

	if not request.headers["authorization"] then
		return http_response(401, "Unauthorized",
		{["WWW-Authenticate"]='Basic realm="WallyWorld"'})
	end
	local user, password = b64_decode(request.headers.authorization
		:match("[^ ]*$") or ""):match("([^:]*):(.*)");
	user = jid_prep(user);
	if not user or not password then return http_response(400, "Bad Request"); end
	local user_node, user_host = jid_split(user)
	if not hosts[user_host] then return http_response(401, "Unauthorized"); end

	module:log("debug", "authz %s", user)
	if not um_test_pw(user_node, user_host, password) then
		return http_response(401, "Unauthorized");
	end

	module:log("debug", "spliting path");
	local path = {};
	for i in string.gmatch(request.url.path, "[^/]+") do
		table.insert(path, i);
	end
	table.remove(path, 1); -- the first /data
	module:log("debug", "split path, got %d parts: %s", #path, table.concat(path, ", "));

	if #path < 3 then
		module:log("debug", "since we need at least 3 parts, adding %s/%s", user_host, user_node);
		table.insert(path, 1, user_node);
		table.insert(path, 1, user_host);
		--return http_response(400, "Bad Request");
	end

	if #path < 3 then
		return http_response(404, "Not Found");
	end

	if user_host ~= path[1] or user_node ~= path[2] then
		-- To only give admins acces to anything, move the inside of this block after authz
		module:log("debug", "%s wants access to %s@%s[%s], is admin?", user, path[2], path[1], path[3])
		if not is_admin(user, path[1]) then
			return http_response(403, "Forbidden");
		end
	end

	local data = dm_load(path[2], path[1], path[3]);
	
	data = data or dm_list_load(path[2], path[1], path[3]);

	if data and encoders[path[4] or "json"] then 
		return {
			status = "200 OK",
			body = encoders[path[4] or "json"](data) .. "\n",
			headers = {["content-type"] = "text/plain; charset=utf-8"}
			--headers = {["content-type"] = encoders[data[4] or "json"].mime .. "; charset=utf-8"}
			-- FIXME a little nicer that the above
			-- Also, would be cooler to use the Accept header, but parsing it ...
		};
	else
		return http_response(404, "Not Found");
	end
end

local function setup()
	local ports = module:get_option("data_access_ports") or { 5280 };
	require "net.httpserver".new_from_config(ports, handle_request, { base = "data" });
end
if prosody.start_time then -- already started
	setup();
else
	prosody.events.add_handler("server-started", setup);
end
