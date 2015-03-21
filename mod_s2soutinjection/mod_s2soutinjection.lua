local st = require"util.stanza";
local new_ip = require"util.ip".new_ip;
local new_outgoing = require"core.s2smanager".new_outgoing;
local bounce_sendq = module:depends"s2s".route_to_new_session.bounce_sendq;
local s2sout = module:depends"s2s".route_to_new_session.s2sout;

local injected = module:get_option("s2s_connect_overrides");

local function isip(addr)
	return not not (addr and addr:match("^%d+%.%d+%.%d+%.%d+$") or addr:match("^[%x:]*:[%x:]-:[%x:]*$"));
end

module:hook("route/remote", function(event)
	local from_host, to_host, stanza = event.from_host, event.to_host, event.stanza;
	local inject = injected and injected[to_host];
	if not inject then return end
	log("debug", "opening a new outgoing connection for this stanza");
	local host_session = new_outgoing(from_host, to_host);

	-- Store in buffer
	host_session.bounce_sendq = bounce_sendq;
	host_session.sendq = { {tostring(stanza), stanza.attr.type ~= "error" and stanza.attr.type ~= "result" and st.reply(stanza)} };
	log("debug", "stanza [%s] queued until connection complete", tostring(stanza.name));

	local ip_hosts, srv_hosts = {}, {};
	host_session.srv_hosts = srv_hosts;
	host_session.srv_choice = 0;

	if type(inject) == "string" then inject = { inject } end

	for _, item in ipairs(inject) do
		local host, port = item[1] or item, tonumber(item[2]) or 5269;
		if isip(host) then
			ip_hosts[#ip_hosts+1] = { ip = new_ip(host), port = port }
		else
			srv_hosts[#srv_hosts+1] = { target = host, port = port }
		end
	end
	if #ip_hosts > 0 then
		host_session.ip_hosts = ip_hosts;
		host_session.ip_choice = 0; -- Incremented by try_next_ip
		s2sout.try_next_ip(host_session);
		return true;
	end

	return s2sout.try_connect(host_session, host_session.srv_hosts[1].target, host_session.srv_hosts[1].port);
end, -2);

