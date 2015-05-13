-- mod_admin_blocklist
--
-- If a local admin has blocked a domain, don't allow s2s to that domain
--
-- Copyright (C) 2015 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--

module:depends("blocklist");

local st = require"util.stanza";
local jid_split = require"util.jid".split;

local admins = module:get_option_inherited_set("admins", {}) /
	function (admin) -- Filter out non-local admins
		local user, host = jid_split(admin);
		if host == module.host then return user; end
	end

local blocklists = module:open_store("blocklist");

local function is_blocked(host)
	for admin in admins do
		local blocklist = blocklists:get(admin);
		if blocklist and blocklist[host] then
			return true;
		end
	end
end

module:hook("route/remote", function (event)
	local origin, stanza = event.origin, event.stanza;
	if is_blocked(event.to_host) then
		if origin and stanza then
			origin.send(st.error_reply(stanza, "cancel", "not-allowed", "Communication with this domain is not allowed"));
			return true;
		end
		return false;
	end
end, 1000);


module:hook("s2s-stream-features", function (event)
	local session = event.origin;
	if is_blocked(session.from_host) then
		session:close("policy-violation");
		return false;
	end
end, 1000);

module:hook("stanza/http://etherx.jabber.org/streams:features", function (event)
	local session = event.origin;
	if is_blocked(session.to_host) then
		session:close("policy-violation");
		return true;
	end
end, 1000);

