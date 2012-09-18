-- XEP-0280: Message Carbons implementation for Prosody
-- Copyright (C) 2011 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local st = require "util.stanza";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local xmlns_carbons = "urn:xmpp:carbons:1";
local xmlns_forward = "urn:xmpp:forward:0";
local host_sessions = hosts[module.host].sessions;

local function toggle_carbons(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type == "set" then
		local state = stanza.tags[1].name;
		module:log("debug", "%s %sd carbons", origin.full_jid, state);
		origin.want_carbons = state == "enable";
		origin.send(st.reply(stanza));
		return true
	end
end
module:hook("iq/self/"..xmlns_carbons..":disable", toggle_carbons);
module:hook("iq/self/"..xmlns_carbons..":enable", toggle_carbons);

local function message_handler(event, c2s)
	local origin, stanza = event.origin, event.stanza;
	local orig_type = stanza.attr.type;
	local orig_to = stanza.attr.to;
	local orig_from = stanza.attr.from;
	
	if not (orig_type == nil
			or orig_type == "normal"
			or orig_type == "chat") then
		return -- No carbons for messages of type error or headline
	end

	local bare_jid, user_sessions;
	local no_carbon_to = {};
	module:log("debug", "Message from %s to %s", tostring(orig_from), tostring(orig_to));
	if c2s then -- Stanza sent by a local client
		bare_jid = (origin.username.."@"..origin.host)
		user_sessions = host_sessions[origin.username];
	else -- Stanza about to be delivered to a local client
		local username, hostname, resource = jid_split(orig_to);
		bare_jid = jid_bare(orig_to);
		user_sessions = host_sessions[username];
		if resource then
			module:log("debug", "Message was to resource %s, it will not get carbon", resource);
			no_carbon_to[resource] = true;
		elseif user_sessions then
			local top_resources = user_sessions.top_resources;
			if top_resources then
				-- These will already receive this message per normal routing rules,
				-- so we skip them to avoid duplicated messages.
				for i=1,#top_resources do
					local resource = top_resources[i].resource;
					module:log("debug", "Not sending carbons to top resource %s", resource);
					no_carbon_to[resource] = true;
				end
			end
		end
	end

	if not user_sessions then
		module:log("debug", "Skip carbons for offline user");
		return -- No use in sending carbons to an offline user
	end

	if not c2s and stanza:get_child("private", xmlns_carbons) then
		stanza:maptags(function(tag)
			return tag.attr.xmlns == xmlns_carbons
				and tag.name == "private" and tag or nil;
		end);
		module:log("debug", "Message tagged private, ignoring");
		return
	end

	-- Create the carbon copy and wrap it as per the Stanza Forwarding XEP
	local copy = st.clone(stanza);
	copy.attr.xmlns = "jabber:client";
	local carbon = st.message{ from = bare_jid, type = orig_type, }
		:tag(c2s and "sent" or "received", { xmlns = xmlns_carbons }):up()
			:tag("forwarded", { xmlns = xmlns_forward })
				:add_child(copy):reset();

	-- And finally, send the carbon to the sessions that should have it.
	user_sessions = user_sessions and user_sessions.sessions;
	for resource, session in pairs(user_sessions) do
		local full_jid = bare_jid .. "/" .. resource;
		if session.want_carbons and ((c2s and session ~= origin) or (not c2s and not no_carbon_to[resource])) then
			carbon.attr.to = full_jid;
			module:log("debug", "Sending carbon to %s", full_jid);
			session.send(carbon);
		end
	end
end

local function c2s_message_handler(event)
	return message_handler(event, true)
end

-- Stanzas sent by local clients
module:hook("pre-message/bare", c2s_message_handler, 1);
module:hook("pre-message/full", c2s_message_handler, 1);
-- Stanzas to local clients
module:hook("message/bare", message_handler, 1);
module:hook("message/full", message_handler, 1);

module:add_feature(xmlns_carbons);
