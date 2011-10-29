local st = require "util.stanza";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local xmlns_carbons = "urn:xmpp:carbons:1";
local xmlns_forward = "urn:xmpp:forward:0";
local host_sessions = hosts[module.host].sessions;

-- TODO merge message handlers into one somehow

module:hook("iq/self/"..xmlns_carbons..":enable", function(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type == "set" then
		module:log("debug", "%s enabled carbons", origin.full_jid);
		origin.want_carbons = true;
		origin.send(st.reply(stanza));
		return true
	end
end);

module:hook("iq/self/"..xmlns_carbons..":disable", function(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type == "set" then
		module:log("debug", "%s disabled carbons", origin.full_jid);
		origin.want_carbons = nil;
		origin.send(st.reply(stanza));
		return true
	end
end);

function c2s_message_handler(event)
	local origin, stanza = event.origin, event.stanza;
	local orig_type = stanza.attr.type;
	local orig_to = stanza.attr.to;
	
	if not (orig_type == nil
			or orig_type == "normal"
			or orig_type == "chat") then
		return
	end

	local bare_jid, user_sessions;
	if origin.type == "s2s" then
		bare_jid = jid_bare(stanza.attr.from);
		user_sessions = host_sessions[jid_split(orig_to)];
	else
		bare_jid = (origin.username.."@"..origin.host)
		user_sessions = host_sessions[origin.username];
	end

	if not stanza:get_child("private", xmlns_carbons)
			and not stanza:get_child("forwarded", xmlns_forward) then
		user_sessions = user_sessions and user_sessions.sessions;
		for resource, session in pairs(user_sessions) do
			local full_jid = bare_jid .. "/" .. resource;
			if session ~= origin and session.want_carbons then
				local msg = st.clone(stanza);
				msg.attr.xmlns = msg.attr.xmlns or "jabber:client";
				local fwd = st.message{
							from = bare_jid,
							to = full_jid,
							type = orig_type,
						}
					:tag("forwarded", { xmlns = xmlns_forward })
						:tag("received", { xmlns = xmlns_carbons }):up()
							:add_child(msg);
				core_route_stanza(origin, fwd);
			end
		end
	end
end

function s2c_message_handler(event)
	local origin, stanza = event.origin, event.stanza;
	local orig_type = stanza.attr.type;
	local orig_to = stanza.attr.to;
	
	if not (orig_type == nil
			or orig_type == "normal"
			or orig_type == "chat") then
		return
	end

	local full_jid, bare_jid = orig_to, jid_bare(orig_to);
	local username, hostname, resource = jid_split(full_jid);
	local user_sessions = username and host_sessions[username];
	if not user_sessions or hostname ~= module.host then
		return
	end

	local no_carbon_to = {};
	if resource then
		no_carbon_to[resource] = true;
	else
		local top_resources = user_sessions.top_resources;
		for i=1,top_resources do
			no_carbon_to[top_resources[i]] = true;
		end
	end

	if not stanza:get_child("private", xmlns_carbons)
			and not stanza:get_child("forwarded", xmlns_forward) then
		user_sessions = user_sessions and user_sessions.sessions;
		for resource, session in pairs(user_sessions) do
			local full_jid = bare_jid .. "/" .. resource;
			if not no_carbon_to[resource] and session.want_carbons then
				local msg = st.clone(stanza);
				msg.attr.xmlns = msg.attr.xmlns or "jabber:client";
				local fwd = st.message{
							from = bare_jid,
							to = full_jid,
							type = orig_type,
						}
					:tag("forwarded", { xmlns = xmlns_forward })
						:tag("received", { xmlns = xmlns_carbons }):up()
							:add_child(msg);
				core_route_stanza(origin, fwd);
			end
		end
	end
end

-- Stanzas sent by local clients
module:hook("pre-message/bare", c2s_message_handler, 1);
module:hook("pre-message/full", c2s_message_handler, 1);
-- Stanszas to local clients
module:hook("message/bare", s2c_message_handler, 1); -- this will suck
module:hook("message/full", s2c_message_handler, 1);

module:add_feature(xmlns_carbons);
