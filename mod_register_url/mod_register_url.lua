-- Registration Redirect module for Prosody
-- 
-- Redirects IP addresses not in the whitelist to a web page to complete the registration.

local st = require "util.stanza";

function reg_redirect(event)
	local ip_wl = module:get_option("registration_whitelist") or { "127.0.0.1" };
	local url = module:get_option("registration_url");
	local test_ip;

	for i,ip in ipairs(ip_wl) do 
		if event.origin.ip == ip then test_ip = true; end
		break; 
	end
	
	if not test_ip and url ~= nil then
		local reply = st.reply(event.stanza);
		reply:tag("query", {xmlns = "jabber:iq:register"})
			:tag("instructions"):text("Please visit "..url.." to register an account on this server."):up()
			:tag("x", {xmlns = "jabber:x:oob"}):up()
				:tag("url"):text(url):up();
		event.origin.send(reply);
		return true;
	end
end

module:hook("stanza/iq/jabber:iq:register:query", reg_redirect, 10);
