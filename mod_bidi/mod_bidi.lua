-- Bidirectional Server-to-Server Connections
-- http://xmpp.org/extensions/xep-0288.html
-- Copyright (C) 2013 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--
local s2smanager = require"core.s2smanager";
local add_filter = require "util.filters".add_filter;
local st = require "util.stanza";
local jid_split = require"util.jid".prepped_split;

local xmlns_bidi_feature = "urn:xmpp:features:bidi"
local xmlns_bidi = "urn:xmpp:bidi";
local noop = function () end
local core_process_stanza = prosody.core_process_stanza or core_process_stanza;
local traceback = debug.traceback;

local function handleerr(err) log("error", "Traceback[s2s]: %s: %s", tostring(err), traceback()); end
local function handlestanza(session, stanza)
	if stanza.attr.xmlns == "jabber:client" then --COMPAT: Prosody pre-0.6.2 may send jabber:client
		stanza.attr.xmlns = nil;
	end
	-- stanza = session.filter("stanzas/in", stanza);
	if stanza then
		return xpcall(function () return core_process_stanza(session, stanza) end, handleerr);
	end
end

local function new_bidi(origin)
	local bidi_session, remote_host;
	origin.log("debug", "Creating bidirectional session wrapper");
	if origin.direction == "incoming" then -- then we create an "outgoing" bidirectional session
		local conflicting_session = hosts[origin.to_host].s2sout[origin.from_host]
		if conflicting_session then
			conflicting_session.log("info", "We already have an outgoing connection to %s, closing it...", origin.from_host);
			conflicting_session:close{ condition = "conflict", text = "Replaced by bidirectional stream" }
			s2smanager.destroy_session(conflicting_session);
		end
		remote_host = origin.from_host;
		bidi_session = s2smanager.new_outgoing(origin.to_host, origin.from_host)
	else -- outgoing -- then we create an "incoming" bidirectional session
		remote_host = origin.to_host;
		bidi_session = s2smanager.new_incoming(origin.conn)
		bidi_session.to_host = origin.from_host;
		bidi_session.from_host = origin.to_host;
		add_filter(origin, "stanzas/in", function(stanza)
			if stanza.attr.xmlns ~= nil then return stanza end
			local _, host = jid_split(stanza.attr.from);
			if host ~= remote_host then return stanza end
			handlestanza(bidi_session, stanza);
		end, 1);
	end
	origin.bidi_session = bidi_session;
	bidi_session.sends2s = origin.sends2s;
	bidi_session.bounce_sendq = noop;
	bidi_session.notopen = nil;
	bidi_session.is_bidi = true;
	bidi_session.bidi_session = false;
	bidi_session.orig_session = origin;
	bidi_session.secure = origin.secure;
	bidi_session.cert_identity_status = origin.cert_identity_status;
	bidi_session.cert_chain_status = origin.cert_chain_status;
	bidi_session.close = function(...)
		return origin.close(...);
	end

	bidi_session.log("info", "Bidirectional session established");
	s2smanager.make_authenticated(bidi_session, remote_host);
	return bidi_session;
end

-- Incoming s2s
module:hook("s2s-stream-features", function(event)
	local origin, features = event.origin, event.features;
	if not origin.is_bidi and not hosts[module.host].s2sout[origin.from_host] then
		module:log("debug", "Announcing support for bidirectional streams");
		features:tag("bidi", { xmlns = xmlns_bidi_feature }):up();
	end
end);

module:hook("stanza/urn:xmpp:bidi:bidi", function(event)
	local origin = event.session or event.origin;
	if not origin.is_bidi and not origin.bidi_session then
		module:log("debug", "%s requested bidirectional stream", origin.from_host);
		origin.do_bidi = true;
		return true;
	end
end);

-- Outgoing s2s
module:hook("stanza/http://etherx.jabber.org/streams:features", function(event)
	local origin = event.session or event.origin;
	if not ( origin.bidi_session or origin.is_bidi or origin.do_bidi)
	and event.stanza:get_child("bidi", xmlns_bidi_feature) then
		module:log("debug", "%s supports bidirectional streams", origin.to_host);
		origin.sends2s(st.stanza("bidi", { xmlns = xmlns_bidi }));
		origin.do_bidi = true;
	end
end, 160);

function enable_bidi(event)
	local session = event.session;
	if session.do_bidi and not ( session.is_bidi or session.bidi_session ) then
		session.do_bidi = nil;
		new_bidi(session);
	end
end

module:hook("s2sin-established", enable_bidi);
module:hook("s2sout-established", enable_bidi);

function disable_bidi(event)
	local session = event.session;
	if session.bidi_session then
		local bidi_session = session.bidi_session;
		session.bidi_session, bidi_session.orig_session = nil, nil;
		session.log("debug", "Tearing down bidirectional stream");
		s2smanager.destroy_session(bidi_session, event.reason);
	elseif session.orig_session then
		local orig_session = session.orig_session;
		orig_session.bidi_session, session.orig_session = nil, nil;
		orig_session.log("debug", "Tearing down bidirectional stream");
		s2smanager.destroy_session(orig_session, event.reason);
	end
end

module:hook("s2sin-destroyed", disable_bidi);
module:hook("s2sout-destroyed", disable_bidi);

