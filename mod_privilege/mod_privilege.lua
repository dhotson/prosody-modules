-- XEP-0356 (Privileged Entity)
-- Copyright (C) 2015 Jérôme Poisson
--
-- This module is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.


local jid = require("util/jid")
local set = require("util/set")
local st = require("util/stanza")
local roster_manager = require("core/rostermanager")

local _ALLOWED_ROSTER = set.new({'none', 'get', 'set', 'both'})
local _ROSTER_GET_PERM = set.new({'get', 'both'})
local _ROSTER_SET_PERM = set.new({'set', 'both'})
local _ALLOWED_MESSAGE = set.new({'none', 'outgoing'})
local _ALLOWED_PRESENCE = set.new({'none', 'managed_entity', 'roster'})
local _TO_CHECK = {roster=_ALLOWED_ROSTER, message=_ALLOWED_MESSAGE, presence=_ALLOWED_PRESENCE}
local _PRIV_ENT_NS = 'urn:xmpp:privilege:1'


module:log("debug", "Loading privileged entity module ");

--> Permissions management <--

privileges = module:get_option("privileged_entities", {})

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

function on_presence(event)
	-- Permission are already checked at this point,
	-- we only advertise them to the entity
	local session, stanza = event.origin, event.stanza;
	if session.privileges then
		advertise_perm(session.full_jid, session.privileges)
	end
end

module:hook('authentication-success', on_auth)
module:hook('component-authenticated', on_auth)
module:hook('presence/initial', on_presence)


--> roster permission <--

module:hook("iq-get/bare/jabber:iq:roster:query", function(event)
	local session, stanza = event.origin, event.stanza;
	if not stanza.attr.to then
		-- we don't want stanzas addressed to /self
		return;
	end
	
	if session.privileges and _ROSTER_GET_PERM:contains(session.privileges.roster) then
		module:log("debug", "Roster get from allowed privileged entity received")
		-- following code is adapted from mod_remote_roster
		local node, host = jid.split(stanza.attr.to);
		local roster = roster_manager.load_roster(node, host);
		
		local reply = st.reply(stanza):query("jabber:iq:roster");
		for entity_jid, item in pairs(roster) do
			if entity_jid and entity_jid ~= "pending" then
				local node, host = jid.split(entity_jid);
					reply:tag("item", {
						jid = entity_jid,
						subscription = item.subscription,
						ask = item.ask,
						name = item.name,
					});
					for group in pairs(item.groups) do
						reply:tag("group"):text(group):up();
					end
					reply:up(); -- move out from item
			end
		end
		session.send(reply);
	else
	    module:log("warn", "Entity "..tostring(session.full_jid).." try to get roster without permission")
		session.send(st.error_reply(stanza, 'auth', 'forbidden'))
	end
	
	return true

end);
