-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

if module:get_host_type() ~= "component" then
	error("proxy65 should be loaded as a component, please see http://prosody.im/doc/components", 0);
end

local jid_split = require "util.jid".split;
local st = require "util.stanza";
local componentmanager = require "core.componentmanager";
local config_get = require "core.configmanager".get;
local connlisteners = require "net.connlisteners";
local adns, dns = require "net.adns", require "net.dns";
local add_task = require "util.timer".add_task;
local max_dns_depth = config.get("*", "core", "dns_max_depth") or 3;
local dns_timeout = config.get("*", "core", "dns_timeout") or 60;
local sha1 = require "util.hashes".sha1;

local host, name = module:get_host(), "SOCKS5 Bytestreams Service";
local sessions, transfers, component, replies_cache = {}, {}, nil, {};

local proxy_port = config_get(host, "core", "proxy65_port") or 5000;
local proxy_interface = config_get(host, "core", "proxy65_interface") or "*";
local proxy_address = config_get(host, "core", "proxy65_address") or (proxy_interface ~= "*" and proxy_interface) or module.host;

local connlistener = { default_port = proxy_port, 
			default_interface = proxy_interface,
			default_mode = "*a" };

function connlistener.listener(conn, data)
	local session = sessions[conn] or {};
	
	if session.setup == false and data ~= nil and data:sub(1):byte() == 0x05 and data:len() > 2 then
		local nmethods = data:sub(2):byte();
		local methods = data:sub(3);
		local supported = false;
		for i=1, nmethods, 1 do
			if(methods:sub(i):byte() == 0x00) then -- 0x00 == method: NO AUTH
				supported = true;
				break;
			end
		end
		if(supported) then
			module:log("debug", "new session found ... ")
			session.setup = true;
			sessions[conn] = session;
			conn.write(string.char(5, 0));
		end
		return;
	end
	if session.setup then
		if session.sha ~= nil and transfers[session.sha] ~= nil then
			local sha = session.sha;
			if transfers[sha].activated == true and transfers[sha].initiator == conn and transfers[sha].target ~= nil then
				transfers[sha].target.write(data);
				return;
			end
		end
		if data ~= nil and data:len() == 0x2F and  -- 40 == length of SHA1 HASH, and 7 other bytes => 47 => 0x2F
			data:sub(1):byte() == 0x05 and -- SOCKS5 has 5 in first byte
			data:sub(2):byte() == 0x01 and -- CMD must be 1
			data:sub(3):byte() == 0x00 and -- RSV must be 0
			data:sub(4):byte() == 0x03 and -- ATYP must be 3
			data:sub(5):byte() == 40 and -- SHA1 HASH length must be 64 (0x40)
			data:sub(-2):byte() == 0x00 and -- PORT must be 0, size 2 byte
			data:sub(-1):byte() == 0x00 		
		then
			local sha = data:sub(6, 45); -- second param is not count! it's the ending index (included!)
			if transfers[sha] == nil then
				transfers[sha] = {};
				transfers[sha].activated = false;
				transfers[sha].target = conn;
				session.sha = sha;
				module:log("debug", "target connected ... ");
			elseif transfers[sha].target ~= nil then
				transfers[sha].initiator = conn;
				session.sha = sha;
				module:log("debug", "initiator connected ... ");
			end
			conn.write(string.char(5, 0, 0, 3, sha:len()) .. sha .. string.char(0, 0)); -- VER, REP, RSV, ATYP, BND.ADDR (sha), BND.PORT (2 Byte)
		end
	end
end

function connlistener.disconnect(conn, err)
	if sessions[conn] then
		-- Clean up any session-related stuff here
		sessions[conn] = nil;
	end
end

local function get_disco_info(stanza)
	local reply = replies_cache.disco_info;
	if reply == nil then
	 	reply = st.iq({type='result', from=host}):query("http://jabber.org/protocol/disco#info")
			:tag("identity", {category='proxy', type='bytestreams', name=name}):up()
			:tag("feature", {var="http://jabber.org/protocol/bytestreams"});
		replies_cache.disco_info = reply;
	end

	reply.attr.id = stanza.attr.id;
	reply.attr.to = stanza.attr.from;
	return reply;
end

local function get_disco_items(stanza)
	local reply = replies_cache.disco_items;
	if reply == nil then
	 	reply = st.iq({type='result', from=host}):query("http://jabber.org/protocol/disco#items");
		replies_cache.disco_info = reply;
	end
	
	reply.attr.id = stanza.attr.id;
	reply.attr.to = stanza.attr.from;
	return reply;
end

local function get_stream_host(stanza)
	local reply = replies_cache.stream_host;
	local sid = stanza.tags[1].attr.sid;
	if reply == nil then
		reply = st.iq({type="result", from=host})
			:query("http://jabber.org/protocol/bytestreams")
			:tag("streamhost", {jid=host, host=proxy_address, port=proxy_port}); -- TODO get the correct data
		replies_cache.stream_host = reply;
	end
	
	reply.attr.id = stanza.attr.id;
	reply.attr.to = stanza.attr.from;
	reply.tags[1].attr.sid = sid;
	return reply;
end

module.unload = function()
	componentmanager.deregister_component(host);
	connlisteners.deregister(module.host .. ':proxy65');
end

local function set_activation(stanza)
	local from, to, sid, reply = nil;
	from = stanza.attr.from;
	if stanza.tags[1] ~= nil and tostring(stanza.tags[1].name) == "query" then
		if stanza.tags[1].attr ~= nil then
			sid = stanza.tags[1].attr.sid;
		end
		if stanza.tags[1].tags[1] ~= nil and tostring(stanza.tags[1].tags[1].name) == "activate" then
			to = stanza.tags[1].tags[1][1];
		end
	end
	if from ~= nil and to ~= nil and sid ~= nil then
		reply = st.iq({type="result", from=host});
		reply.attr.id = stanza.attr.id;
	end
	return reply, from, to, sid;
end

function handle_to_domain(origin, stanza)
	local to_node, to_host, to_resource = jid_split(stanza.attr.to);
	if to_node == nil then
		local type = stanza.attr.type;
		if type == "error" or type == "result" then return; end
		if stanza.name == "iq" and type == "get" then
			local xmlns = stanza.tags[1].attr.xmlns
			if xmlns == "http://jabber.org/protocol/disco#info" then
				origin.send(get_disco_info(stanza));
				return true;
			elseif xmlns == "http://jabber.org/protocol/disco#items" then
				origin.send(get_disco_items(stanza));
				return true;
			elseif xmlns == "http://jabber.org/protocol/bytestreams" then
				origin.send(get_stream_host(stanza));
				return true;
			end
		elseif stanza.name == "iq" and type == "set" then
			local reply, from, to, sid = set_activation(stanza);
			if reply ~= nil and from ~= nil and to ~= nil and sid ~= nil then
				local sha = sha1(sid .. from .. to, true);
				if transfers[sha] == nil then
					module:log("error", "transfers[sha]: nil");
				elseif(transfers[sha] ~= nil and transfers[sha].initiator ~= nil and transfers[sha].target ~= nil) then
					origin.send(reply);
					transfers[sha].activated = true;
				end
			end
		end
	end
	return;
end

if not connlisteners.register(module.host .. ':proxy65', connlistener) then
	error("mod_proxy65: Could not establish a connection listener. Check your configuration please.");
	error(" one possible cause for this would be that two proxy65 components share the same port.");
end

connlisteners.start(module.host .. ':proxy65');
component = componentmanager.register_component(host, handle_to_domain);
