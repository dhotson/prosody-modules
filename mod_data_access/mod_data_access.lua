-- HTTP Access to datamanager
-- By Kim Alvefur <zash@zash.se>

local t_concat = table.concat;
local jid_prep = require "util.jid".prep;
local jid_split = require "util.jid".split;
local um_test_pw = require "core.usermanager".test_password;
local is_admin = require "core.usermanager".is_admin
local dm_load = require "util.datamanager".load;
local dm_store = require "util.datamanager".store;
local dm_list_load = require "util.datamanager".list_load;
local dm_list_append = require "util.datamanager".list_append;
local b64_decode = require "util.encodings".base64.decode;
local http = require "net.http";
local urldecode  = http.urldecode;
local urlencode  = http.urlencode;
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
local decoders = {
	lua = require "util.serialization".deserialize,
	json = require "util.json".decode,
};
local content_type_map = {
	["text/x-lua"] = "lua"; lua = "text/x-lua";
	["application/json"] = "json"; json = "application/json";
}
--[[
encoders.xml = function(data)
	return "<?xml version='1.0' encoding='utf-8'?><todo:write-this-serializer/>";
end --]]

local allowed_methods = {
	GET = true, "GET",
	PUT = true, "PUT",
	POST = true, "POST",
}

local function handle_request(method, body, request)
	if not allowed_methods[method] then
		return http_response(405, "Method Not Allowed", {["Allow"] = t_concat(allowed_methods, ", ")});
	end

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

	local p_host, p_user, p_store, p_type = unpack(path);
	
	if not p_store or not p_store:match("^[%a_]+$") then
		return http_response(404, "Not Found");
	end

	if user_host ~= path[1] or user_node ~= path[2] then
		-- To only give admins acces to anything, move the inside of this block after authz
		module:log("debug", "%s wants access to %s@%s[%s], is admin?", user, p_user, p_host, p_store)
		if not is_admin(user, p_host) then
			return http_response(403, "Forbidden");
		end
	end

	if method == "GET" then
		local data = dm_load(p_user, p_host, p_store);

		data = data or dm_load_list(p_user, p_host, p_store);

		--TODO Use the Accept header
		content_type = p_type or "json";
		if data and encoders[content_type] then 
			return {
				status = "200 OK",
				body = encoders[content_type](data) .. "\n",
				headers = {["content-type"] = content_type_map[content_type].."; charset=utf-8"}
			};
		else
			return http_response(404, "Not Found");
		end
	else -- POST or PUT
		if not body then
			return http_response(400, "Bad Request")
		end
		local content_type, content = request.headers["content-type"], body;
		content_type = content_type and content_type_map[content_type]
		module:log("debug", "%s: %s", content_type, tostring(content));
		content = content_type and decoders[content_type] and decoders[content_type](content);
		module:log("debug", "%s: %s", type(content), tostring(content));
		if not content then
			return http_response(400, "Bad Request")
		end
		local ok, err
		if method == "PUT" then
			ok, err = dm_store(p_user, p_host, p_store, content);
		elseif method == "POST" then
			ok, err = dm_list_append(p_user, p_host, p_store, content);
		end
		if ok then
			return http_response(201, "Created", { Location = t_concat({"/data",p_host,p_user,p_store}, "/") });
		else
			return { status = "500 Internal Server Error", body = err }
		end
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
