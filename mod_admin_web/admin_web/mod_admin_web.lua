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
--   <encrypted>
--     <valid/> / <invalid/>
--   </encrypted>
--   <compressed/>
--   <in/> / <out/>
-- </session>

local st = require "util.stanza";
local uuid_generate = require "util.uuid".generate;
local is_admin = require "usermanager".is_admin;
local pubsub = require "util.pubsub";
local httpserver = require "net.httpserver";
local jid_bare = require "util.jid".bare;
local lfs = require "lfs";
local open = io.open;
local stat = lfs.attributes;

module:set_global();

local service = {};

local http_base = (prosody.paths.plugins or "./plugins") .. "/admin_web/www_files";

local xmlns_adminsub = "http://prosody.im/adminsub";
local xmlns_c2s_session = "http://prosody.im/streams/c2s";
local xmlns_s2s_session = "http://prosody.im/streams/s2s";

local response_301 = { status = "301 Moved Permanently" };
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

function add_client(session, host)
	local name = session.full_jid;
	local id = idmap[name];
	if not id then
		id = uuid_generate();
		idmap[name] = id;
	end
	local item = st.stanza("item", { id = id }):tag("session", {xmlns = xmlns_c2s_session, jid = name}):up();
	if session.secure then
		item:tag("encrypted"):up();
	end
	if session.compressed then
		item:tag("compressed"):up();
	end
	service[host]:publish(xmlns_c2s_session, host, id, item);
	module:log("debug", "Added client " .. name);
end

function del_client(session, host)
	local name = session.full_jid;
	local id = idmap[name];
	if id then
		local notifier = st.stanza("retract", { id = id });
		service[host]:retract(xmlns_c2s_session, host, id, notifier);
	end
end

function add_host(session, type, host)
	local name = (type == "out" and session.to_host) or (type == "in" and session.from_host);
	local id = idmap[name.."_"..type];
	if not id then
		id = uuid_generate();
		idmap[name.."_"..type] = id;
	end
	local item = st.stanza("item", { id = id }):tag("session", {xmlns = xmlns_s2s_session, jid = name})
		:tag(type):up();
	if session.secure then
		if session.cert_identity_status == "valid" then
			item:tag("encrypted"):tag("valid"):up():up();
		else
			item:tag("encrypted"):tag("invalid"):up():up();
		end
	end
	if session.compressed then
		item:tag("compressed"):up();
	end
	service[host]:publish(xmlns_s2s_session, host, id, item);
	module:log("debug", "Added host " .. name .. " s2s" .. type);
end

function del_host(session, type, host)
	local name = (type == "out" and session.to_host) or (type == "in" and session.from_host);
	local id = idmap[name.."_"..type];
	if id then
		local notifier = st.stanza("retract", { id = id });
		service[host]:retract(xmlns_s2s_session, host, id, notifier);
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

function serve_file(path, base)
	local full_path = http_base..path;
	if stat(full_path, "mode") == "directory" then
		if not path:find("/$") then
			local response = response_301;
			response.headers = { ["Location"] = base .. "/" };
			return response;
		end
		if stat(full_path.."/index.html", "mode") == "file" then
			return serve_file(path.."/index.html");
		end
		return response_403;
	end
	local f, err = open(full_path, "rb");
	if not f then return response_404; end
	local data = f:read("*a");
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
	path_stripped = path:gsub("^/[^/]+", ""); -- Strip /admin/
	return serve_file(path_stripped, path);
end

function module.load()
	local http_conf = config.get("*", "core", "webadmin_http_ports");

	httpserver.new_from_config(http_conf, handle_file_request, { base = "admin" });
end

prosody.events.add_handler("server-started", function ()
	for host_name, host_table in pairs(hosts) do
		service[host_name] = pubsub.new({
			broadcaster = function(node, jids, item) return simple_broadcast(node, jids, item, host_name) end;
			normalize_jid = jid_bare;
			get_affiliation = function(jid) return get_affiliation(jid, host_name) end;
			capabilities = {
				member = {
					create = false;
					publish = false;
					retract = false;
					get_nodes = true;

					subscribe = true;
					unsubscribe = true;
					get_subscription = true;
					get_subscriptions = true;
					get_items = true;

					subscribe_other = false;
					unsubscribe_other = false;
					get_subscription_other = false;
					get_subscriptions_other = false;

					be_subscribed = true;
					be_unsubscribed = true;

					set_affiliation = false;
				};

				owner = {
					create = true;
					publish = true;
					retract = true;
					get_nodes = true;

					subscribe = true;
					unsubscribe = true;
					get_subscription = true;
					get_subscriptions = true;
					get_items = true;

					subscribe_other = true;
					unsubscribe_other = true;
					get_subscription_other = true;
					get_subscriptions_other = true;

					be_subscribed = true;
					be_unsubscribed = true;

					set_affiliation = true;
				};
			};
		});

		if not select(2, service[host_name]:get_nodes(true))[xmlns_s2s_session] then
			local ok, errmsg = service[host_name]:create(xmlns_s2s_session, true);
			if not ok then
				module:log("warn", "Could not create node " .. xmlns_s2s_session .. ": " .. tostring(errmsg));
			else
				service[host_name]:set_affiliation(xmlns_s2s_session, true, host_name, "owner")
			end
		end

		for remotehost, session in pairs(host_table.s2sout) do
			if session.type ~= "s2sout_unauthed" then
				add_host(session, "out", host_name);
			end
		end
		for session in pairs(incoming_s2s) do
			if session.to_host == host_name then
				add_host(session, "in", host_name);
			end
		end

		if not select(2, service[host_name]:get_nodes(true))[xmlns_c2s_session] then
			local ok, errmsg = service[host_name]:create(xmlns_c2s_session, true);
			if not ok then
				module:log("warn", "Could not create node " .. xmlns_c2s_session .. ": " .. tostring(errmsg));
			else
				service[host_name]:set_affiliation(xmlns_c2s_session, true, host_name, "owner")
			end
		end

		for username, user in pairs(host_table.sessions or {}) do
			for resource, session in pairs(user.sessions or {}) do
				add_client(session, host_name);
			end
		end

		host_table.events.add_handler("iq/host/http://prosody.im/adminsub:adminsub", function(event)
			local origin, stanza = event.origin, event.stanza;
			local adminsub = stanza.tags[1];
			local action = adminsub.tags[1];
			local reply;
			if action.name == "subscribe" then
				local ok, ret = service[host_name]:add_subscription(action.attr.node, stanza.attr.from, stanza.attr.from);
				if ok then
					reply = st.reply(stanza)
						:tag("adminsub", { xmlns = xmlns_adminsub });
				else
					reply = st.error_reply(stanza, "cancel", ret);
				end
			elseif action.name == "unsubscribe" then
				local ok, ret = service[host_name]:remove_subscription(action.attr.node, stanza.attr.from, stanza.attr.from);
				if ok then
					reply = st.reply(stanza)
						:tag("adminsub", { xmlns = xmlns_adminsub });
				else
					reply = st.error_reply(stanza, "cancel", ret);
				end
			elseif action.name == "items" then
				local node = action.attr.node;
				local ok, ret = service[host_name]:get_items(node, stanza.attr.from);
				if not ok then
					return origin.send(st.error_reply(stanza, "cancel", ret));
				end

				local data = st.stanza("items", { node = node });
				for _, entry in pairs(ret) do
					data:add_child(entry);
				end
				if data then
					reply = st.reply(stanza)
						:tag("adminsub", { xmlns = xmlns_adminsub })
							:add_child(data);
				else
					reply = st.error_reply(stanza, "cancel", "item-not-found");
				end
			elseif action.name == "adminfor" then
				local data = st.stanza("adminfor");
				for host_name in pairs(hosts) do
					if is_admin(stanza.attr.from, host_name) then
						data:tag("item"):text(host_name):up();
					end
				end
				reply = st.reply(stanza)
					:tag("adminsub", { xmlns = xmlns_adminsub })
						:add_child(data);
			else
				reply = st.error_reply(stanza, "feature-not-implemented");
			end
			return origin.send(reply);
		end);

		host_table.events.add_handler("resource-bind", function(event)
			add_client(event.session, host_name);
		end);

		host_table.events.add_handler("resource-unbind", function(event)
			del_client(event.session, host_name);
			service[host_name]:remove_subscription(xmlns_c2s_session, host_name, event.session.full_jid);
			service[host_name]:remove_subscription(xmlns_s2s_session, host_name, event.session.full_jid);
		end);

		host_table.events.add_handler("s2sout-established", function(event)
			add_host(event.session, "out", host_name);
		end);

		host_table.events.add_handler("s2sin-established", function(event)
			add_host(event.session, "in", host_name);
		end);

		host_table.events.add_handler("s2sout-destroyed", function(event)
			del_host(event.session, "out", host_name);
		end);

		host_table.events.add_handler("s2sin-destroyed", function(event)
			del_host(event.session, "in", host_name);
		end);

	end
end);

function simple_broadcast(node, jids, item, host)
	item = st.clone(item);
	item.attr.xmlns = nil; -- Clear the pubsub namespace
	local message = st.message({ from = host, type = "headline" })
		:tag("event", { xmlns = xmlns_adminsub .. "#event" })
			:tag("items", { node = node })
				:add_child(item);
	for jid in pairs(jids) do
		module:log("debug", "Sending notification to %s", jid);
		message.attr.to = jid;
		core_post_stanza(hosts[host], message);
	end
end

function get_affiliation(jid, host)
	local bare_jid = jid_bare(jid);
	if is_admin(bare_jid, host) then
		return "member";
	else
		return "none";
	end
end
