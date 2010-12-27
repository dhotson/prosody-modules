-- Copyright (C) 2010 Florian Zeitz
--
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

-- <session xmlns="http://prosody.im/streams/c2s" jid="alice@example.com/brussels">
--   <encrypted/>
--   <compressed/>
-- </session>

-- <session xmlns="http://prosody.im/streams/s2s" jid="example.com">
--   <encrypted/>
--   <compressed/>
--   <in/> / <out/>
-- </session>

local stanza = require "util.stanza";
local uuid_generate = require "util.uuid".generate;
local httpserver = require "net.httpserver";
local lfs = require "lfs";
local open = io.open;
local stat = lfs.attributes;

local host = module:get_host();
local service = config.get("*", "core", "webadmin_pubsub_host") or ("pubsub." .. host);

local http_base = (prosody.paths.plugins or "./plugins/") .. "admin_web/www_files";

local xmlns_c2s_session = "http://prosody.im/streams/c2s";
local xmlns_s2s_session = "http://prosody.im/streams/s2s";

local response_400 = { status = "400 Bad Request", body = "<h1>Bad Request</h1>Sorry, we didn't understand your request :(" };
local response_403 = { status = "403 Forbidden", body = "<h1>Forbidden</h1>You don't have permission to view the contents of this directory :(" };
local response_404 = { status = "404 Not Found", body = "<h1>Page Not Found</h1>Sorry, we couldn't find what you were looking for :(" };

local mime_map = {
	html = "text/html";
	xml = "text/xml";
	js = "text/javascript";
	css = "text/css";
};

local idmap = {};

function add_client(session)
	local name = session.full_jid;
	local id = idmap[name];
	if not id then
		id = uuid_generate();
		idmap[name] = id;
	end
	local item = stanza.stanza("item", { id = id }):tag("session", {xmlns = xmlns_c2s_session, jid = name}):up();
	if session.secure then
		item:tag("encrypted"):up();
	end
	if session.compressed then
		item:tag("compressed"):up();
	end
	hosts[service].modules.pubsub.service:publish(xmlns_c2s_session, service, id, item);
	module:log("debug", "Added client " .. name);
end

function del_client(session)
	local name = session.full_jid;
	local id = idmap[name];
	if id then
		local notifier = stanza.stanza("retract", { id = id });
		hosts[service].modules.pubsub.service:retract(xmlns_c2s_session, service, id, notifier);
	end
end

function add_host(session, type)
	local name = (type == "out" and session.to_host) or (type == "in" and session.from_host);
	local id = idmap[name.."_"..type];
	if not id then
		id = uuid_generate();
		idmap[name.."_"..type] = id;
	end
	local item = stanza.stanza("item", { id = id }):tag("session", {xmlns = xmlns_s2s_session, jid = name})
		:tag(type):up();
	if session.secure then
		item:tag("encrypted"):up();
	end
	if session.compressed then
		item:tag("compressed"):up();
	end
	hosts[service].modules.pubsub.service:publish(xmlns_s2s_session, service, id, item);
	module:log("debug", "Added host " .. name .. " s2s" .. type);
end

function del_host(session, type)
	local name = (type == "out" and session.to_host) or (type == "in" and session.from_host);
	local id = idmap[name.."_"..type];
	if id then
		local notifier = stanza.stanza("retract", { id = id });
		hosts[service].modules.pubsub.service:retract(xmlns_s2s_session, service, id, notifier);
	end
end

local function preprocess_path(path)
	if path:sub(1,1) ~= "/" then
		path = "/"..path;
	end
	local level = 0;
	for component in path:gmatch("([^/]+)/") do
		if component == ".." then
			level = level - 1;
		elseif component ~= "." then
			level = level + 1;
		end
		if level < 0 then
			return nil;
		end
	end
	return path;
end

function serve_file(path)
	local full_path = http_base..path;
	if stat(full_path, "mode") == "directory" then
		if stat(full_path.."/index.html", "mode") == "file" then
			return serve_file(path.."/index.html");
		end
		return response_403;
	end
	local f, err = open(full_path, "rb");
	if not f then return response_404; end
	local data = f:read("*a");
	data = data:gsub("%%PUBSUBHOST%%", service);
	f:close();
	if not data then
		return response_403;
	end
	local ext = path:match("%.([^.]*)$");
	local mime = mime_map[ext]; -- Content-Type should be nil when not known
	return {
		headers = { ["Content-Type"] = mime; };
		body = data;
	};
end

local function handle_file_request(method, body, request)
	local path = preprocess_path(request.url.path);
	if not path then return response_400; end
	path = path:gsub("^/[^/]+", ""); -- Strip /admin/
	return serve_file(path);
end

function module.load()
	local host_session = prosody.hosts[host];
	local http_conf = config.get("*", "core", "webadmin_http_ports");

	httpserver.new_from_config(http_conf, handle_file_request, { base = "admin" });
end

module:hook("server-started", function ()
	if not select(2, hosts[service].modules.pubsub.service:get_nodes(service))[xmlns_s2s_session] then
		local ok, errmsg = hosts[service].modules.pubsub.service:create(xmlns_s2s_session, service);
		if not ok then
			module:log("warn", "Could not create node " .. xmlns_s2s_session .. ": " .. tostring(errmsg));
		end
	end

	for remotehost, session in pairs(host_session.s2sout) do
		if session.type ~= "s2sout_unauthed" then
			add_host(session, "out");
		end
	end
	for session in pairs(incoming_s2s) do
		if session.to_host == host then
			add_host(session, "in");
		end
	end

	if not select(2, hosts[service].modules.pubsub.service:get_nodes(service))[xmlns_c2s_session] then
		local ok, errmsg = hosts[service].modules.pubsub.service:create(xmlns_c2s_session, service);
		if not ok then
			module:log("warn", "Could not create node " .. xmlns_c2s_session .. ": " .. tostring(errmsg));
		end
	end

	for username, user in pairs(host_session.sessions or {}) do
		for resource, session in pairs(user.sessions or {}) do
			add_client(session);
		end
	end
end);

module:hook("resource-bind", function(event)
	add_client(event.session);
end);

module:hook("resource-unbind", function(event)
	del_client(event.session);
end);

module:hook("s2sout-established", function(event)
	add_host(event.session, "out");
end);

module:hook("s2sin-established", function(event)
	add_host(event.session, "in");
end);

module:hook("s2sout-destroyed", function(event)
	del_host(event.session, "out");
end);

module:hook("s2sin-destroyed", function(event)
	del_host(event.session, "in");
end);
