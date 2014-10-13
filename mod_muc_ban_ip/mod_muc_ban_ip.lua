module:set_global();

local jid_bare = require "util.jid".bare;
local st = require "util.stanza";
local xmlns_muc_user = "http://jabber.org/protocol/muc#user";

local ip_bans = module:shared("bans");
local full_sessions = prosody.full_sessions;

local function ban_ip(session, from)
	local ip = session.ip;
	if not ip then
		module:log("warn", "Failed to ban IP (IP unknown) for %s", session.full_jid);
		return;
	end
	local banned_from = ip_bans[ip];
	if not banned_from then
		banned_from = {};
		ip_bans[ip] = banned_from;
	end
	banned_from[from] = true;
	module:log("debug", "Banned IP address %s from %s", ip, from);
end

function check_for_incoming_ban(event)
	local stanza = event.stanza;
	local to_session = full_sessions[stanza.attr.to];
	if to_session then
		local directed = to_session.directed;
		local from = stanza.attr.from;
		if directed and directed[from] and stanza.attr.type == "unavailable" then
			-- This is a stanza from somewhere we sent directed presence to (may be a MUC)
			local x = stanza:get_child("x", xmlns_muc_user);
			if x then
				for status in x:childtags("status") do
					if status.attr.code == '301' then
						ban_ip(to_session, jid_bare(from));
					end
				end
			end
		end
	end
end

function check_for_ban(event)
	local ip = event.origin.ip;
	local to = jid_bare(event.stanza.attr.to);
	if ip_bans[ip] and ip_bans[ip][to] then
		event.origin.send(st.error_reply(event.stanza, "auth", "forbidden")
			:tag("x", { xmlns = xmlns_muc_user })
				:tag("status", { code = '301' }));
		return true;
	end
	module:log("debug", "Not banned: %s from %s", ip, to)
end

function module.add_host(module)
	module:hook("presence/full", check_for_incoming_ban);
	module:hook("pre-presence/full", check_for_ban);
end
