-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

if module:get_host_type() ~= "component" then
	error("proxy65 should be loaded as a component, please see http://prosody.im/doc/components", 0);
end

local _host = module:get_host();
local _name = "SOCKS5 Bytestreams Service";

local jid_split = require "util.jid".split;
local st = require "util.stanza";
local register_component = require "core.componentmanager".register_component;
local deregister_component = require "core.componentmanager".deregister_component;
local configmanager = require "core.configmanager";

local replies_cache = {};

--[[
<iq type='result' 
    from='streamhostproxy.example.net' 
    to='initiator@example.com/foo' 
    id='proxy_info'>
  <query xmlns='http://jabber.org/protocol/disco#info'>
    <identity category='proxy'
              type='bytestreams'
              name='SOCKS5 Bytestreams Service'/>
    <feature var='http://jabber.org/protocol/bytestreams'/>
  </query>
</iq>
]]--
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

--[[
<iq type='result' 
    from='streamhostproxy.example.net' 
    to='initiator@example.com/foo' 
    id='discover'>
  <query xmlns='http://jabber.org/protocol/bytestreams'>
         sid='vxf9n471bn46'>
    <streamhost 
        jid='streamhostproxy.example.net' 
        host='24.24.24.1' 
        zeroconf='_jabber.bytestreams'/>
  </query>
</iq>
]]--
local function get_stream_host(stanza)
	local reply = replies_cache.stream_host;
	if reply == nil then
		reply = st.iq({type="result", from=_host})
			:query("http://jabber.org/protocol/bytestreams")
			:tag("streamhost", {jid=_host, host="24.24.24.1", zeroconf="_jabber.bytestreams"}); -- TODO get the correct data
		replies_cache.stream_host = reply;
	end
	
	reply.attr.id = stanza.attr.id;
	reply.attr.to = stanza.attr.from;
	reply.tags[1].attr.sid = stanza.tags[1].attr.sid;
	return reply;
end

module.unload = function()
	deregister_component(_host);
end

module:add_item("proxy", {jid=_host, name=_name})

component = register_component(_host, function(origin, stanza)
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
			elseif xmlns == "http://jabber.org/protocol/bytestreams" and stanza.tags[1].attr.sid ~= nil then
				origin.send(get_stream_host(stanza));
				return true;
			end
		end
	end
	return;
end);