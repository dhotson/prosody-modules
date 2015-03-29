local st = require "util.stanza";

local keepalive_servers = module:get_option_set("keepalive_servers");
local keepalive_interval = module:get_option_number("keepalive_interval", 60);

local host = module.host;

local function send_pings()
	for remote_domain, session in pairs(hosts[host].s2sout) do
		if session.type == "s2sout" -- as opposed to _unauthed
		and (not(keepalive_servers) or keepalive_servers:contains(remote_domain)) then
			session.sends2s(st.iq({ to = remote_domain, type = "get", from = host, id = "keepalive" })
				:tag("ping", { xmlns = "urn:xmpp:ping" })
			);
			-- Note: We don't actually check if this comes back.
		end
	end

	for session in pairs(prosody.incoming_s2s) do
		if session.type == "s2sin" -- as opposed to _unauthed
		and (not(keepalive_servers) or keepalive_servers:contains(session.from_host)) then
			session.sends2s " ";
			-- If the connection is dead, this should make it time out.
		end
	end
	return keepalive_interval;
end

if module.add_timer then -- 0.9
	module:add_timer(keepalive_interval, send_pings);
else -- 0.8
	local timer = require "util.timer";
	local unloaded;
	timer.add_task(keepalive_interval, function()
		if not unloaded then
			return send_pings()
		end
	end);
	function module.unload()
		unloaded = true
	end
end
