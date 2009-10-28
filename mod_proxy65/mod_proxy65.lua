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
local component_register = require "core.componentmanager".register_component;
local component_deregister = require "core.componentmanager".deregister_component;
local configmanager = require "core.configmanager";
local config_get = require "core.configmanager".get;
local connlisteners_register = require "net.connlisteners".register;
local connlisteners_start = require "net.connlisteners".start;
local connlisteners_deregister = require "net.connlisteners".deregister;
local adns, dns = require "net.adns", require "net.dns";
local add_task = require "util.timer".add_task;
local max_dns_depth = config.get("*", "core", "dns_max_depth") or 3;
local dns_timeout = config.get("*", "core", "dns_timeout") or 60;
local serialize = require "util.serialization".serialize;
local sha1 = require "util.hashes".sha1;

local replies_cache = {};
local _host = module:get_host();
local _name = "SOCKS5 Bytestreams Service";
local connlistener = {registered=false};
local _config = {};
local sessions = {};
local transfers = {};
local component;

_config.port = config_get(_host, "core", "port");
_config.interface = config_get(_host, "core", "interface");

if _config.port == nil then
	_config.port = 5000;
end

local function bin2hex(bin)
	return bin:gsub(".", function (c) return ("%02x"):format(c:byte()); end)
end

function new_session(conn)
	local w = function(s) conn.write(s:gsub("\n", "\r\n")); end;
	local session = { conn = conn;
			send = function (t) w(tostring(t)); end;
			print = function (t) w("| "..tostring(t).."\n"); end;
			disconnect = function () conn.close(); end;
			};
	
	return session;
end

function connlistener.listener(conn, data)
	local session = sessions[conn];
	
	if session == nil and data ~= nil and data:sub(1):byte() == 0x05 and data:len() > 2 then
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
			session = new_session(conn);
			sessions[conn] = session;
			session.send(string.char(5, 0));
		end
		return;
	end
	if session ~= nil then
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
			session.send(string.char(5, 0, 0, 3, sha:len()) .. sha .. string.char(0, 0)); -- VER, REP, RSV, ATYP, BND.ADDR (sha), BND.PORT (2 Byte)
		end
	end
end

function connlistener.disconnect(conn, err)

end

local function get_disco_info(stanza)
	local reply = replies_cache.disco_info;
	if reply == nil then
	 	reply = st.iq({type='result', from=_host}):query("http://jabber.org/protocol/disco#info")
			:tag("identity", {category='proxy', type='bytestreams', name=_name}):up()
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
	 	reply = st.iq({type='result', from=_host}):query("http://jabber.org/protocol/disco#items");
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
		reply = st.iq({type="result", from=_host})
			:query("http://jabber.org/protocol/bytestreams")
			:tag("streamhost", {jid=_host, host=_config.interface, port=_config.port}); -- TODO get the correct data
		replies_cache.stream_host = reply;
	end
	
	reply.attr.id = stanza.attr.id;
	reply.attr.to = stanza.attr.from;
	reply.tags[1].attr.sid = sid;
	return reply;
end

module.unload = function()
	component_deregister(_host);
	connlisteners_deregister("proxy65");
end

local function set_activation(stanza)
	local from = nil;
	local to = nil;
	local sid = nil;
	local reply = nil;
	if stanza.attr ~= nil then
		from = stanza.attr.from;
	end
	if stanza.tags[1] ~= nil and tostring(stanza.tags[1].name) == "query" then
		if stanza.tags[1].attr ~= nil then
			sid = stanza.tags[1].attr.sid;
		end
		if stanza.tags[1].tags[1] ~= nil and tostring(stanza.tags[1].tags[1].name) == "activate" then
			to = stanza.tags[1].tags[1][1];
		end
	end
	if from ~= nil and to ~= nil and sid ~= nil then
		reply = st.iq({type="result", from=_host});
		reply.attr.id = stanza.attr.id;
	end
	return reply, from, to, sid;
end

local function forward(initiator, target)
	module:log("debug", "forward it ....");
end


local function register()
	connlistener.default_port = _config.port;
	connlistener.default_interface = "*"; 
	connlistener.default_mode = "*a";
	connlistener.registered = connlisteners_register('proxy65', connlistener);
	if(connlistener.registered == false) then
		error("Proxy65: Could not establish a connection listener. Check your configuration please.");
	else
		connlistener.handler = connlisteners_start('proxy65');
		module:add_item("proxy65", {jid=_host, name=_name})
		component = component_register(_host, function(origin, stanza)
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
		end);
	end
end

local function getDefaultIP(host)
	local handle;
	handle = adns.lookup(function (reply)
		handle = nil;

		-- COMPAT: This is a compromise for all you CNAME-(ab)users :)
		if not (reply and reply[#reply] and reply[#reply].a) then
			local count = max_dns_depth;
			reply = dns.peek(host, "CNAME", "IN");
			while count > 0 and reply and reply[#reply] and not reply[#reply].a and reply[#reply].cname do
				module:log("debug", "Looking up %s (DNS depth is %d)", tostring(reply[#reply].cname), count);
				reply = dns.peek(reply[#reply].cname, "A", "IN") or dns.peek(reply[#reply].cname, "CNAME", "IN");
				count = count - 1;
			end
		end
		-- end of CNAME resolving

		if reply and reply[#reply] and reply[#reply].a then
			module:log("debug", "DNS reply for %s gives us %s", host, reply[#reply].a);
			_config.interface = reply[#reply].a
			return register();
		else
			module:log("debug", "DNS lookup failed to get a response for %s", host);
			if host:find(".") ~= nil then
				host = host:gsub("^[^%.]*%.", "");
				if host:find(".") ~= nil then -- still one dot left?
					return getDefaultIP(host);
				end
			end
			error("Proxy65: Could not get an interface to bind to. Please configure one.");
		end
	end, host, "A", "IN");

	-- Set handler for DNS timeout
	add_task(dns_timeout, function ()
		if handle then
			adns.cancel(handle, true);
		end
	end);
	return true;
end

if _config.interface ~= nil then
	register();
else
	getDefaultIP(_host); -- try to DNS lookup module:host()
end
