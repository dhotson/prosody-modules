-- Filter out servers which gets choppy and buggy when it comes to starttls.

local bad_servers = module:get_option_set("tls_s2s_blacklist", {})
local bad_servers_ip = module:get_option_set("tls_s2s_blacklist_ip", {})

local function disable_tls_for_baddies_in(event)
	local session = event.origin
	if bad_servers:contains(session.from_host) or bad_servers_ip:contains(session.conn:ip()) then 
		module:log("debug", "disabling tls on incoming stream from %s...", tostring(session.from_host));
		session.conn.starttls = nil
	end
end

local function disable_tls_for_baddies_out(event)
	local session = event.origin
	if bad_servers:contains(session.to_host) then
		module:log("debug", "disabling tls on outgoing stream from %s...", tostring(session.to_host));
		session.conn.starttls = nil
	end
end

module:hook("s2s-stream-features", disable_tls_for_baddies_in, 600)
module:hook("stanza/http://etherx.jabber.org/streams:features", disable_tls_for_baddies_out, 600)
