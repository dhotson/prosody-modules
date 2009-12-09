-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza";
local is_admin = require "core.usermanager".is_admin;
local commands = {};

module:add_feature("http://jabber.org/protocol/commands");

module:hook("iq/host/http://jabber.org/protocol/disco#items:query", function (event)
    local origin, stanza = event.origin, event.stanza;
    local privileged = is_admin(event.stanza.attr.from) or is_admin(stanza.attr.from, stanza.attr.to); -- TODO: Is this correct, or should is_admin be changed?
    if stanza.attr.type == "get" and stanza.tags[1].attr.node and stanza.tags[1].attr.node == "http://jabber.org/protocol/commands" then
		reply = st.reply(stanza);
		reply:tag("query", {xmlns="http://jabber.org/protocol/disco#items", node="http://jabber.org/protocol/commands"})
		for i = 1, #commands do
			-- module:log("info", "adding command %s", commands[i].name);
			if (commands[i].permission == "admin" and privileged) or (commands[i].permission == "user") then
				reply:tag("item", {name=commands[i].name, node=commands[i].node, jid=module:get_host()});
				reply:up();
			end
		end
        origin.send(reply);
        return true;
    end 
end, 500);

module:hook("iq/host", function (event)
    local origin, stanza = event.origin, event.stanza;
    if stanza.attr.type == "set" and stanza.tags[1] and stanza.tags[1].name == "command" then 
        local node = stanza.tags[1].attr.node
	local privileged = is_admin(event.stanza.attr.from) or is_admin(stanza.attr.from, stanza.attr.to); -- TODO: Is this correct, or should is_admin be changed?
	for i = 1, #commands do
		if commands[i].node == node then
			-- check whether user has permission to execute this command first
			if commands[i].permission == "admin" and not privileged then
				origin.send(st.error_reply(stanza, "auth", "forbidden", "You don't have permission to execute this command"):up()
					:add_child(commands[i]:cmdtag("canceled")
						:tag("note", {type="error"}):text("You don't have permission to execute this command")));
				return true
			end
			-- User has permission now execute the command
			return commands[i].handler(commands[i], origin, stanza);
		end
	end
    end 
end, 500);

module:hook("item-added/adhoc", function (event)
	commands[ #commands + 1] = event.item;
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
