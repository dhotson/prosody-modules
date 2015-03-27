local jid = require("util/jid")
local set = require("util/set")
local st = require("util/stanza")
local _ALLOWED_ROSTER = set.new({'none', 'get', 'set', 'both'})
local _ALLOWED_MESSAGE = set.new({'none', 'outgoing'})
local _ALLOWED_PRESENCE = set.new({'none', 'managed_entity', 'roster'})
local _TO_CHECK = {roster=_ALLOWED_ROSTER, message=_ALLOWED_MESSAGE, presence=_ALLOWED_PRESENCE}
local _PRIV_ENT_NS = 'urn:xmpp:privilege:1'

module:log("info", "Loading privileged entity module ");

privileges = module:get_option("privileged_entities", {})

module:log("warn", "Connection, HOST="..tostring(module:get_host()).." ("..tostring(module:get_host_type())..")")

function advertise_perm(to_jid, perms)
	-- send <message/> stanza to advertise permissions
	-- as expained in section 4.2
	local message = st.message({to=to_jid})
					  :tag("privilege", {xmlns=_PRIV_ENT_NS})
	
	for _, perm in pairs({'roster', 'message', 'presence'}) do
		if perms[perm] then
			message:tag("perm", {access=perm, type=perms[perm]}):up()
		end
	end
	
	module:send(message)
end

function on_auth(event)
	-- Check if entity is privileged according to configuration,
	-- and set session.privileges accordingly
	
	local session = event.session
	local bare_jid = jid.join(session.username, session.host)
	module:log("info", "======>>> on_auth, type="..tostring(event.session.type)..", jid="..tostring(bare_jid));

	local ent_priv = privileges[bare_jid]
	if ent_priv ~= nil then
		module:log("debug", "Entity is privileged")
		for perm_type, allowed_values in pairs(_TO_CHECK) do
			local value = ent_priv[perm_type]
			if value ~= nil then
				if not allowed_values:contains(value) then
					module:log('warn', 'Invalid value for '..perm_type..' privilege: ['..value..']')
					module:log('warn', 'Setting '..perm_type..' privilege to none')
					ent_priv[perm_type] = nil
				end
				if value == 'none' then
					ent_priv[perm_type] = nil
				end
			end
		end
		if session.type == "component" then
			-- we send the message stanza only for component
			-- it will be sent at first <presence/> for other entities
			advertise_perm(bare_jid, ent_priv)
		end
	end

	session.privileges = ent_priv
end

module:hook('authentication-success', on_auth)
module:hook('component-authenticated', on_auth)
