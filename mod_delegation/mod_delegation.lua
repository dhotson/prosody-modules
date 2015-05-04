-- XEP-0355 (Namespace Delegation)
-- Copyright (C) 2015 Jérôme Poisson
--
-- This module is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.

-- This module manage namespace delegation, a way to delegate server features
-- to an external entity/component. Only the admin mode is implemented so far

-- TODO: client mode

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
local _FORWARDED_NS = 'urn:xmpp:forward:0'
local _DISCO_NS = 'http://jabber.org/protocol/disco#info'
local _DATA_NS = 'jabber:x:data'

local _MAIN_SEP = '::'
local _BARE_SEP = ':bare:'
local _MAIN_PREFIX = _DELEGATION_NS.._MAIN_SEP
local _BARE_PREFIX = _DELEGATION_NS.._BARE_SEP
local _PREFIXES = {_MAIN_PREFIX, _BARE_PREFIX}

local disco_nest

module:log("debug", "Loading namespace delegation module ");

--> Configuration management <--

local ns_delegations = module:get_option("delegations", {})

local jid2ns = {}
for namespace, ns_data in pairs(ns_delegations) do
	-- "connected" contain the full jid of connected managing entity
	ns_data.connected = nil
	if ns_data.jid then
		if jid2ns[ns_data.jid] == nil then
			jid2ns[ns_data.jid] = {}
		end
		jid2ns[ns_data.jid][namespace] = ns_data
		module:log("debug", "Namespace %s is delegated%s to %s", namespace, ns_data.filtering and " (with filtering)" or "", ns_data.jid)
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

	for namespace, ns_data  in pairs(jid2ns[to_jid]) do
		if ns_data.connected == to_jid then
			have_delegation = true
			message:tag("delegated", {namespace=namespace})
			if type(ns_data.filtering) == "table" then
				for _, attribute in pairs(ns_data.filtering) do
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
		for namespace, ns_data in pairs(jid2ns[jid_]) do
			if ns_data.connected == nil then
				ns_data.connected = entity_jid
				disco_nest(namespace, entity_jid)
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


--> delegated namespaces hook <--

local managing_ent_error
local stanza_cache = {} -- we cache original stanza to build reply

local function managing_ent_result(event)
	-- this function manage iq results from the managing entity
	-- it do a couple of security check before sending the
	-- result to the managed entity
	local stanza = event.stanza
	if stanza.attr.to ~= module.host then
		module:log("warn", 'forwarded stanza result has "to" attribute not addressed to current host, id conflict ?')
		return
	end
	module:unhook("iq-result/host/"..stanza.attr.id, managing_ent_result)
	module:unhook("iq-error/host/"..stanza.attr.id, managing_ent_error)

	-- lot of checks to do...
	local delegation = stanza.tags[1]
	if #stanza ~= 1 or delegation.name ~= "delegation" or
		delegation.attr.xmlns ~= _DELEGATION_NS then
		module:log("warn", "ignoring invalid iq result from managing entity %s", stanza.attr.from)
		stanza_cache[stanza.attr.from][stanza.attr.id] = nil
		return true
	end

	local forwarded = delegation.tags[1]
	if #delegation ~= 1 or forwarded.name ~= "forwarded" or
		forwarded.attr.xmlns ~= _FORWARDED_NS then
		module:log("warn", "ignoring invalid iq result from managing entity %s", stanza.attr.from)
		stanza_cache[stanza.attr.from][stanza.attr.id] = nil
		return true
	end

	local iq = forwarded.tags[1]
	if #forwarded ~= 1 or iq.name ~= "iq" or #iq ~= 1 then
		module:log("warn", "ignoring invalid iq result from managing entity %s", stanza.attr.from)
		stanza_cache[stanza.attr.from][stanza.attr.id] = nil
		return true
	end

	local namespace = iq.tags[1].xmlns
	local ns_data = ns_delegations[namespace]
	local original = stanza_cache[stanza.attr.from][stanza.attr.id]
	stanza_cache[stanza.attr.from][stanza.attr.id] = nil

	if stanza.attr.from ~= ns_data.connected or iq.attr.type ~= "result" or
		iq.attr.id ~= original.attr.id or iq.attr.to ~= original.attr.from then
		module:log("warn", "ignoring forbidden iq result from managing entity %s, please check that the component is no trying to do something bad (stanza: %s)", stanza.attr.from, tostring(stanza))
		module:send(st.error_reply(original, 'cancel', 'service-unavailable'))
		return true
	end

	-- at this point eveything is checked,
	-- and we (hopefully) can send the the result safely
	module:send(iq)
end

function managing_ent_error(event)
	local stanza = event.stanza
	if stanza.attr.to ~= module.host then
		module:log("warn", 'Stanza result has "to" attribute not addressed to current host, id conflict ?')
		return
	end
	module:unhook("iq-result/host/"..stanza.attr.id, managing_ent_result)
	module:unhook("iq-error/host/"..stanza.attr.id, managing_ent_error)
	local original = stanza_cache[stanza.attr.from][stanza.attr.id]
	stanza_cache[stanza.attr.from][stanza.attr.id] = nil
	module:log("warn", "Got an error after forwarding stanza to "..stanza.attr.from)
	module:send(st.error_reply(original, 'cancel', 'service-unavailable'))
end

local function forward_iq(stanza, ns_data)
	local to_jid = ns_data.connected
	stanza.attr.xmlns = 'jabber:client'
	local iq_stanza  = st.iq({ from=module.host, to=to_jid, type="set" })
		:tag("delegation", { xmlns=_DELEGATION_NS })
		:tag("forwarded", { xmlns=_FORWARDED_NS })
		:add_child(stanza)
	local iq_id = iq_stanza.attr.id
	-- we save the original stanza to check the managing entity result
	if not stanza_cache[to_jid] then stanza_cache[to_jid] = {} end
	stanza_cache[to_jid][iq_id] = stanza
	module:hook("iq-result/host/"..iq_id, managing_ent_result)
	module:hook("iq-error/host/"..iq_id, managing_ent_error)
	module:log("debug", "stanza forwarded")
	module:send(iq_stanza)
end

local function iq_hook(event)
	-- general hook for all the iq which forward delegated ones
	-- and continue normal behaviour else. If a namespace is
	-- delegated but managing entity is offline, a service-unavailable
	-- error will be sent, as requested by the XEP
	local session, stanza = event.origin, event.stanza
	if #stanza == 1 and stanza.attr.type == 'get' or stanza.attr.type == 'set' then
		local namespace = stanza.tags[1].attr.xmlns
		local ns_data = ns_delegations[namespace]

		if ns_data then
			if stanza.attr.from == ns_data.connected then
				-- we don't forward stanzas from managing entity itself
				return
			end
			if ns_data.filtering then
				local first_child = stanza.tags[1]
				for _, attribute in ns_data.filtering do
					-- if any filtered attribute if not present,
					-- we must continue the normal bahaviour
					if not first_child.attr[attribute] then
						-- Filtered attribute is not present, we do normal workflow
						return;
					end
				end
			end
			if not ns_data.connected then
				module:log("warn", "No connected entity to manage "..namespace)
				session.send(st.error_reply(stanza, 'cancel', 'service-unavailable'))
			else
				forward_iq(stanza, ns_data)
			end
			return true
		else
			-- we have no delegation, we continue normal behaviour
			return
		end
	end
end

module:hook("iq/self", iq_hook, 2^32)
module:hook("iq/bare", iq_hook, 2^32)
module:hook("iq/host", iq_hook, 2^32)


--> discovery nesting <--

-- disabling internal features/identities

local function find_form_type(stanza)
	local form_type = nil
	for field in stanza.childtags('field', 'jabber:x:data') do
		if field.attr.var=='FORM_TYPE' and field.attr.type=='hidden' then
			local value = field:get_child('value')
			if not value then
				module:log("warn", "No value found in FORM_TYPE field: "..tostring(stanza))
			else
				form_type=value.get_text()
			end
		end
	end
	return form_type
end

-- modules whose features/identities are managed by delegation
local disabled_modules = set.new()
local disabled_identities = set.new()

local function identity_added(event)
	local source = event.source
	if disabled_modules:contains(source) then
		local item = event.item
		local category, type_, name = item.category, item.type, item.name
		module:log("debug", "Removing (%s/%s%s) identity because of delegation", category, type_, name and "/"..name or "")
		disabled_identities:add(item)
		source:remove_item("identity", item)
	end
end

local function feature_added(event)
	local source, item = event.source, event.item
	for namespace, _ in pairs(ns_delegations) do
		if source ~= module and string.sub(item, 1, #namespace) == namespace then
			module:log("debug", "Removing %s feature which is delegated", item)
			source:remove_item("feature", item)
			disabled_modules:add(source)
			if source.items and source.items.identity then
				-- we remove all identities added by the source module
				-- that can cause issues if the module manages several features/identities
				-- but this case is probably rare (or doesn't happen at all)
				-- FIXME: any better way ?
				for _, identity in pairs(source.items.identity) do
					identity_added({source=source, item=identity})
				end
			end
		end
	end
end

local function extension_added(event)
	local source, stanza = event.source, event.item
	local form_type = find_form_type(stanza)
	if not form_type then return; end

	for namespace, _ in pairs(ns_delegations) do
		if source ~= module and string.sub(form_type, 1, #namespace) == namespace then
			module:log("debug", "Removing extension which is delegated: %s", tostring(stanza))
			source:remove_item("extension", stanza)
		end
	end
end

-- for disco nesting (see § 7.2) we need to remove internal features
-- we use handle_items as it allow to remove already added features
-- and catch the ones which can come later
module:handle_items("feature", feature_added, function(_) end)
module:handle_items("identity", identity_added, function(_) end, false)
module:handle_items("extension", extension_added, function(_) end)


-- managing entity features/identities collection

local disco_error
local bare_features = set.new()
local bare_identities = {}
local bare_extensions = {}

local function disco_result(event)
	-- parse result from disco nesting request
	-- and fill module features/identities and bare_features/bare_identities accordingly
	local session, stanza = event.origin, event.stanza
	if stanza.attr.to ~= module.host then
		module:log("warn", 'Stanza result has "to" attribute not addressed to current host, id conflict ?')
		return
	end
	module:unhook("iq-result/host/"..stanza.attr.id, disco_result)
	module:unhook("iq-error/host/"..stanza.attr.id, disco_error)
	local query = stanza:get_child("query", _DISCO_NS)
	if not query or not query.attr.node then
		session.send(st.error_reply(stanza, 'modify', 'not-acceptable'))
		return true
	end

	local node = query.attr.node
	local main

	if string.sub(node, 1, #_MAIN_PREFIX) == _MAIN_PREFIX then
		main=true
	elseif string.sub(node, 1, #_BARE_PREFIX) == _BARE_PREFIX then
		main=false
	else
		module:log("warn", "Unexpected node: "..node)
		session.send(st.error_reply(stanza, 'modify', 'not-acceptable'))
		return true
	end

	for feature in query:childtags("feature") do
		local namespace = feature.attr.var
		if main then
			module:add_feature(namespace)
		else
			bare_features:add(namespace)
		end
	end
	for identity in query:childtags("identity") do
		local category, type_, name = identity.attr.category, identity.attr.type, identity.attr.name
		if main then
			module:add_identity(category, type_, name)
		else
			table.insert(bare_identities, {category=category, type=type_, name=name})
		end
	end
	for extension in query:childtags("x", _DATA_NS) do
		if main then
			module:add_extension(extension)
		else
			table.insert(bare_extensions, extension)
		end
	end
end

function disco_error(event)
	local stanza = event.stanza
	if stanza.attr.to ~= module.host then
		module:log("warn", 'Stanza result has "to" attribute not addressed to current host, id conflict ?')
		return
	end
	module:unhook("iq-result/host/"..stanza.attr.id, disco_result)
	module:unhook("iq-error/host/"..stanza.attr.id, disco_error)
	module:log("warn", "Got an error while requesting disco for nesting to "..stanza.attr.from)
	module:log("warn", "Ignoring disco nesting")
end

function disco_nest(namespace, entity_jid)
	-- manage discovery nesting (see § 7.2)

	-- first we reset the current values
	if module.items then
		module.items['feature'] = nil
		module.items['identity'] = nil
		module.items['extension'] = nil
		bare_features = set.new()
		bare_identities = {}
		bare_extensions = {}
	end

	for _, prefix in ipairs(_PREFIXES) do
		local node = prefix..namespace

		local iq = st.iq({from=module.host, to=entity_jid, type='get'})
			:tag('query', {xmlns=_DISCO_NS, node=node})

		local iq_id = iq.attr.id

		module:hook("iq-result/host/"..iq_id, disco_result)
		module:hook("iq-error/host/"..iq_id, disco_error)
		module:send(iq)
	end
end

-- disco to bare jids special case

module:hook("account-disco-info", function(event)
	-- this event is called when a disco info request is done on a bare jid
	-- we get the final reply and filter delegated features/identities/extensions
	local reply = event.reply;
	reply.tags[1]:maptags(function(child)
		if child.name == 'feature' then
			local feature_ns = child.attr.var
			for namespace, _ in pairs(ns_delegations) do
				if string.sub(feature_ns, 1, #namespace) == namespace then
					module:log("debug", "Removing feature namespace %s which is delegated", feature_ns)
					return nil
				end
			end
		elseif child.name == 'identity' then
			for item in disabled_identities:items() do
				if item.category == child.attr.category
					and item.type == child.attr.type
					-- we don't check name, because mod_pep use a name for main disco, but not in account-disco-info hook
					-- and item.name == child.attr.name
				then
					module:log("debug", "Removing (%s/%s%s) identity because of delegation", item.category, item.type, item.name and "/"..item.name or "")
					return nil
				end
			end
		elseif child.name == 'x' and child.attr.xmlns == _DATA_NS then
			local form_type = find_form_type(child)
			if form_type then
				for namespace, _ in pairs(ns_delegations) do
					if string.sub(form_type, 1, #namespace) == namespace then
						module:log("debug", "Removing extension which is delegated: %s", tostring(child))
						return nil
					end
				end
			end

		end
		return child
	end)
	for feature in bare_features:items() do
		reply:tag('feature', {var=feature}):up()
	end
	for _, item in ipairs(bare_identities) do
		reply:tag('identity', {category=item.category, type=item.type, name=item.name}):up()
	end
	for _, stanza in ipairs(bare_extensions) do
		reply:add_child(stanza)
	end

end, -2^32);
