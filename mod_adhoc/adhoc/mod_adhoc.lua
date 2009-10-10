-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza";
local commands = {};

module:add_feature("http://jabber.org/protocol/commands");

module:hook("iq/host/http://jabber.org/protocol/disco#items:query", function (event)
    local origin, stanza = event.origin, event.stanza;
    if stanza.attr.type == "get" and stanza.tags[1].attr.node and stanza.tags[1].attr.node == "http://jabber.org/protocol/commands" then
		reply = st.reply(stanza);
		reply:tag("query", {xmlns="http://jabber.org/protocol/disco#items", node="http://jabber.org/protocol/commands"})
		for i = 1, #commands do
			-- module:log("info", "adding command %s", commands[i].name);
			reply:tag("item", {name=commands[i].name, node=commands[i].node, jid=module:get_host()});
			reply:up();
		end
        origin.send(reply);
        return true;
    end 
end, 500);

module:hook("iq/host", function (event)
    local origin, stanza = event.origin, event.stanza;
    if stanza.attr.type == "set" and stanza.tags[1] and stanza.tags[1].name == "command" then 
        local node = stanza.tags[1].attr.node
		for i = 1, #commands do
			if commands[i].node == node then
				return commands[i].handler(commands[i], origin, stanza);
			end
		end
    end 
end, 500);

module:hook("item-added/adhoc", function (event)
	commands[ # commands + 1] = event.item;
end, 500);

local _G = _G;
local t_remove = _G.table.remove;
module:hook("item-removed/adhoc", function (event)
	for i = 1, #commands do
		if commands[i].node == event.item.node then
			t_remove(commands, i);
			break;
		end
	end
end, 500);
