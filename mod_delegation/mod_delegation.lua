-- XEP-0355 (Namespace Delegation)
-- Copyright (C) 2015 Jérôme Poisson
--
-- This module is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.


local jid = require("util/jid")
local st = require("util/stanza")
local set = require("util/set")

local delegation_session = module:shared("/*/delegation/session")

if delegation_session.connected_cb == nil then
	-- set used to have connected event listeners
	-- which allow a host to react on events from
	-- other hosts
	delegation_session.connected_cb = set.new()
end
local connected_cb = delegation_session.connected_cb

local _DELEGATION_NS = 'urn:xmpp:delegation:1'
-- local _FORWARDED_NS = 'urn:xmpp:forward:0'


module:log("debug", "Loading namespace delegation module ");


--> Configuration management <--

local ns_delegations = module:get_option("delegations", {})

local jid2ns = {}
for namespace, config in pairs(ns_delegations) do
	-- "connected" contain the full jid of connected managing entity
	config.connected = nil
	if config.jid then
		if jid2ns[config.jid] == nil then
			jid2ns[config.jid] = {}
		end
		jid2ns[config.jid][namespace] = config
	else
		module:log("warn", "Ignoring delegation for %s: no jid specified", tostring(namespace))
		ns_delegations[namespace] = nil
	end
end


local function advertise_delegations(session, to_jid)
	-- send <message/> stanza to advertise delegations
	-- as expained in § 4.2
	local message = st.message({from=module.host, to=to_jid})
					  :tag("delegation", {xmlns=_DELEGATION_NS})

	-- we need to check if a delegation is granted because the configuration
	-- can be complicated if some delegations are granted to bare jid
	-- and other to full jids, and several resources are connected.
	local have_delegation = false

	for namespace, config  in pairs(jid2ns[to_jid]) do
		if config.connected == to_jid then
			have_delegation = true
			message:tag("delegated", {namespace=namespace})
			if type(config.filtering) == "table" then
				for _, attribute in pairs(config.filtering) do
					message:tag("attribute", {name=attribute}):up()
				end
				message:up()
			end
		end
	end

	if have_delegation then
		session.send(message)
	end
end

local function set_connected(entity_jid)
	-- set the "connected" key for all namespace managed by entity_jid
	-- if the namespace has already a connected entity, ignore the new one
	local function set_config(jid_)
		for _, config in pairs(jid2ns[jid_]) do
			if config.connected == nil then
				config.connected = entity_jid
			end
		end
	end
	local bare_jid = jid.bare(entity_jid)
	set_config(bare_jid)
	-- We can have a bare jid of a full jid specified in configuration
	-- so we try our luck with both (first connected resource will
	-- manage the namespaces in case of bare jid)
	if bare_jid ~= entity_jid then
		set_config(entity_jid)
		jid2ns[entity_jid] = jid2ns[bare_jid]
	end
end

local function on_presence(event)
	local session = event.origin
	local bare_jid = jid.bare(session.full_jid)

	if jid2ns[bare_jid] or jid2ns[session.full_jid] then
		set_connected(session.full_jid)
		advertise_delegations(session, session.full_jid)
	end
end

local function on_component_connected(event)
	-- method called by the module loaded by the component
	-- /!\ the event come from the component host,
	-- not from the host of this module
	local session = event.session
	local bare_jid = jid.join(session.username, session.host)

	local jid_delegations = jid2ns[bare_jid]
	if jid_delegations ~= nil then
		set_connected(bare_jid)
		advertise_delegations(session, bare_jid)
	end
end

local function on_component_auth(event)
	-- react to component-authenticated event from this host
	-- and call the on_connected methods from all other hosts
	-- needed for the component to get delegations advertising
	for callback in connected_cb:items() do
		callback(event)
	end
end

connected_cb:add(on_component_connected)
module:hook('component-authenticated', on_component_auth)
module:hook('presence/initial', on_presence)
