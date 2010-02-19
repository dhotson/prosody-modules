
-- mod_ipcheck.lua
-- Implementation of XEP-xxxx: Server IP Check <http://xmpp.org/extensions/inbox/sic.html>

local st = require "util.stanza";

module:add_feature("urn:xmpp:sic:0");

module:hook("iq/bare/urn:xmpp:sic:0:ip", function(event)
	local origin, stanza = event.origin, event.stanza;
	if not stanza.attr.to and stanza.attr.type == "get" then
		if stanza.attr.to then
			origin.send(st.error_reply(stanza, "auth", "not-authorized", "You can only ask about your own IP address"));
		elseif origin.ip then
			origin.send(st.reply(stanza):tag("ip", {xmlns='urn:xmpp:sic:0'}):text(origin.ip));
		else
			-- IP addresses should normally be available, but in case they are not
			origin.send(st.error_reply(stanza, "cancel", "item-not-found", "IP address for this session is not available"));
		end
		return true;
	end
end);
