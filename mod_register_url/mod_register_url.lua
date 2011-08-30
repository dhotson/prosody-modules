-- Registration Redirect module for Prosody
-- 
-- Redirects IP addresses not in the whitelist to a web page to complete the registration.

local st = require "util.stanza";

function reg_redirect(event)
	local stanza, origin = event.stanza, event.origin;
	local ip_wl = module:get_option("registration_whitelist") or { "127.0.0.1" };
	local url = module:get_option("registration_url");
	local no_wl = module:get_option_boolean("no_registration_whitelist", false);
	local test_ip = false;

	if not no_wl then
		for i,ip in ipairs(ip_wl) do
			if origin.ip == ip then test_ip = true; end
			break;
		end
	end
	
	if stanza.attr.type == "get" then
		local reply = st.reply(event.stanza);
		reply:query("jabber:iq:register")
			:tag("instructions"):text("Please visit "..url.." to register an account on this server."):up()
			:tag("x", {xmlns = "jabber:x:oob"})
				:tag("url"):text(url);
		origin.send(reply);
		return true;
	else
		origin.send(st.error_reply(stanza, "cancel", "not-authorized"))
		return true
	end
end

module:hook("stanza/iq/jabber:iq:register:query", reg_redirect, 10);
