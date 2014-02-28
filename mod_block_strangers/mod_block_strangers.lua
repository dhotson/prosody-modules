
local jid_split = require "util.jid".split;
local jid_bare = require "util.jid".bare;
local is_contact_subscribed = require "core.rostermanager".is_contact_subscribed;

function check_subscribed(event)
	local stanza = event.stanza;
	local to_user, to_host, to_resource = jid_split(stanza.attr.to);
	local from_jid = jid_bare(stanza.attr.from);
	if to_user and not is_contact_subscribed(to_user, to_host, from_jid) then
		if to_resource and stanza.attr.type == "groupchat" then
			return nil; -- Pass through
		end
		return true; -- Drop stanza
	end
end

module:hook("message/bare", check_subscribed, 200);
module:hook("message/full", check_subscribed, 200);
module:hook("iq/full", check_subscribed, 200);
