local st = require "util.stanza";

local services = module:get_option("external_services");

local xmlns_extdisco = "urn:xmpp:extdisco:1";

module:add_feature(xmlns_extdisco);

module:hook("iq-get/host/"..xmlns_extdisco..":services", function (event)
	local origin, stanza = event.origin, event.stanza;
	local service = stanza:get_child("service", xmlns_extdisco);
	local service_type = service and service.attr.type;
	local reply = st.reply(stanza);
	for host, service_info in pairs(services) do
		if not(service_type) or service_info.type == service_type then
			reply:tag("service", {
				host = host;
				port = service_info.port;
				transport = service_info.transport;
				type = service_info.type;
				username = service_info.username;
				password = service_info.password;
			}):up();
		end
	end
	origin.send(reply);
	return true;
end);

module:hook("iq-get/host/"..xmlns_extdisco..":credentials", function (event)
	local origin, stanza = event.origin, event.stanza;
	local credentials = stanza:get_child("credentials", xmlns_extdisco);
	local host = credentials and credentials.attr.host;
	if not host then
		origin.send(st.error_reply(stanza, "cancel", "bad-request", "No host specified"));
		return true;
	end
	local service_info = services[host];
	if not service_info then
		origin.send(st.error_reply(stanza, "cancel", "item-not-found", "No such service known"));
		return true;
	end
	local reply = st.reply(stanza)
		:tag("credentials")
			:tag("service", {
				host = host;
				username = service_info.username;
				password = service_info.password;
			}):up();
	origin.send(reply);
	return true;
end);
