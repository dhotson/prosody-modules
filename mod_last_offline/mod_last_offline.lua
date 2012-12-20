local datamanager = require "util.datamanager";	
local jid_split = require "util.jid".split;
local time = os.time;
local NULL = {};
local host = module.host;

module:hook("resource-unbind", function(event)
	local session = event.session;
	if session.username then
		datamanager.store(session.username, host, "last_online", {
			timestamp = time(),
		});
	end
end);

local function offline_stamp(event)
	local stanza = event.stanza;
	local node, to_host = jid_split(stanza.attr.from);
	if to_host == host and event.origin == hosts[host] and stanza.attr.type == "unavailable" then
		local timestamp = (datamanager.load(node, host, "last_online") or NULL).timestamp;
		if timestamp then
			stanza:tag("delay", {
				xmlns = "urn:xmpp:delay",
				from = host,
				stamp = datetime.datetime(timestamp),
			}):up();
		end
	end
end

module:hook("pre-presence/bare", offline_stamp);
module:hook("pre-presence/full", offline_stamp);

