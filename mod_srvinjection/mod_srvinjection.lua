local s = require"util.serialization".new"oneline".serialize;

module:set_global();

local adns = require "net.adns";

local map_config = module:get_option("srvinjection") or {};
local map = module:shared "s2s_map"

for host, mapping in pairs(map_config) do
	if type(mapping) == "table" and type(mapping[1]) == "string" and (type(mapping[2]) == "number") then
		local connecthost, connectport = mapping[1], mapping[2] or 5269;
		map[host] = {{
			srv = {
				target = connecthost..".";
				port = connectport;
				priority = 1;
				weight = 0;
			};
		}};
	else
		module:log("warn", "Ignoring invalid SRV injection for host '%s'", host);
		map[host] = nil;
	end
end

local original_lookup = adns.lookup;
function adns.lookup(handler, qname, qtype, qclass)
	module:log("debug", "adns.lookup(%s, %s, %s)", s(qname), s(qtype), s(qclass));
	if qtype == "SRV" then
		local host = qname:match("^_xmpp%-server%._tcp%.(.*)%.$");
		module:log("debug", "qname:match(...) → %s", s(host));
		local mapping = map[host] or map["*"];
		module:log("debug", "map[%s] → %s", s(host), s(mapping));
		local mapping = map[host] or map["*"];
		if mapping then
			handler(mapping);
			return;
		end
	elseif qtype == "A" and (qname == "localhost." or qname == "127.0.0.1.") then
		handler({{ a = "127.0.0.1" }});
		return;
	end
	return original_lookup(handler, qname, qtype, qclass);
end

function module.unload()
	adns.lookup = original_lookup;
end
