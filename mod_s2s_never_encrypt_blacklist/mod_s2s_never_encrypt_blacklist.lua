-- Filter out servers which gets choppy and buggy when it comes to starttls.

local bad_servers = module:get_option_set("tls_s2s_blacklist");

local function disable_tls_for_baddies(event)
	if bad_servers:contains(event.origin.to_host) then event.origin.conn.starttls = nil; end
end

module:hook("stanza/http://etherx.jabber.org/streams:features", disable_tls_for_baddies, 510)
