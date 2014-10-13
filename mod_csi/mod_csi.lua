local st = require "util.stanza";
local csi_feature = st.stanza("csi", { xmlns = "urn:xmpp:csi" });

module:hook("stream-features", function (event)
	if event.origin.username then
		event.features:add_child(csi_feature);
	end
end);

function refire_event(name)
	return function (event)
		if event.origin.username then
			module:fire_event(name, event);
			return true;
		end
	end;
		
end

module:hook("stanza/urn:xmpp:csi:active", refire_event("csi-client-active"));
module:hook("stanza/urn:xmpp:csi:inactive", refire_event("csi-client-inactive"));

