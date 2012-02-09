-- Clients Connection Throttler.
-- Usage:
-- Add the module into modules loaded into the virtual host section
--
-- cthrottler_logins_count = 3 -> number of logins attempt allowed
-- cthrottler_time = 120 -> in x seconds

local time = os.time
local in_count = {}
local logins_count = module:get_option_number("cthrottler_logins_count", 3)
local throttle_time = module:get_option_number("cthrottler_time", 60)

local function handle_sessions(event)
	local session = event.origin

	if not in_count[session.ip] and session.type == "c2s_unauthed" then
		in_count[session.ip] = { t = time(), c = 1 }
	elseif in_count[session.ip] and session.type == "c2s_unauthed" then
		in_count[session.ip].c = in_count[session.ip].c + 1
		
		if in_count[session.ip].c > logins_count and time() - in_count[session.ip].t < throttle_time then
			module:log("error", "Exceeded login count for %s, closing connection", session.ip)
			session:close{ condition = "policy-violation", text = "You exceeded the number of connections/logins allowed in "..throttle_time.." seconds, good bye." }
			return true
		elseif time() - in_count[session.ip].t > throttle_time then
			in_count[session.ip] = nil ; return
		end
	end	
end

module:hook("stanza/urn:ietf:params:xml:ns:xmpp-sasl:auth", handle_sessions, 100)
module:hook("stanza/iq/jabber:iq:auth:query", handle_sessions, 100) -- Legacy?
