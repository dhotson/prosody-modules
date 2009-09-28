-- Prosody IM
-- Copyright (C) 2008-2009 Matthew Wild
-- Copyright (C) 2008-2009 Waqas Hussain
-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local prosody = prosody;
local helpers = require "util/helpers";
local st = require "util.stanza";
local datamanager = require "util.datamanager";
local bare_sessions = bare_sessions;
local util_Jid = require "util.jid";
local jid_bare = util_Jid.bare;
local jid_split = util_Jid.split;
local load_roster = require "core.rostermanager".load_roster;
local to_number = _G.tonumber;

function findNamedList (privacy_lists, name)
	local ret = nil
	if privacy_lists.lists == nil then
		module:log("debug", "no lists loaded.")
		return nil;
	end

	module:log("debug", "searching for list: %s", name);
	for i=1, #privacy_lists.lists do
		if privacy_lists.lists[i].name == name then
			ret = i;
			break;
		end
	end
	return ret;
end

function declineList (privacy_lists, origin, stanza, which)
	module:log("info", "User requests to decline the use of privacy list: %s", which);
	privacy_lists[which] = nil;
	origin.send(st.reply(stanza));
	return true;
end

function activateList (privacy_lists, origin, stanza, which, name)
	module:log("info", "User requests to change the privacy list: %s, to be list named %s", which, name);
	local ret = false;
	local idx = findNamedList(privacy_lists, name);

	if privacy_lists[which] == nil then
		privacy_lists[which] = "";
	end
	
	if privacy_lists[which] ~= name and idx ~= nil then
		privacy_lists[which] = name;
		origin.send(st.reply(stanza));
		ret = true;
	end
	return ret;
end

function deleteList (privacy_lists, origin, stanza, name)
	module:log("info", "User requests to delete privacy list: %s", name);
	local ret = false;
	local idx = findNamedList(privacy_lists, name);

	if idx ~= nil then
		table.remove(privacy_lists.lists, idx);
		origin.send(st.reply(stanza));
		ret = true;
	end
	return ret;
end

local function sortByOrder(a, b)
	if a.order < b.order then
		return true;
	end
	return false;
end

function createOrReplaceList (privacy_lists, origin, stanza, name, entries, roster)
	module:log("info", "User requests to create / replace list named %s, item count: %d", name, #entries);
	local ret = true;
	local idx = findNamedList(privacy_lists, name);
	local bare_jid = origin.username.."@"..origin.host;
	
	if privacy_lists.lists == nil then
		privacy_lists.lists = {};
	end

	if idx == nil then
		idx = #privacy_lists.lists + 1;
	end

	local orderCheck = {};
	local list = {};
	list.name = name;
	list.items = {};

	for _,item in ipairs(entries) do
		if to_number(item.attr.order) == nil or to_number(item.attr.order) < 0 or orderCheck[item.attr.order] ~= nil then
			return "bad-request";
		end
		local tmp = {};
		orderCheck[item.attr.order] = true;
		
		tmp["type"] = item.attr.type;
		tmp["value"] = item.attr.value;
		tmp["action"] = item.attr.action;
		tmp["order"] = to_number(item.attr.order);
		tmp["presence-in"] = false;
		tmp["presence-out"] = false;
		tmp["message"] = false;
		tmp["iq"] = false;
		
		if #item.tags > 0 then
			for _,tag in ipairs(item.tags) do
				tmp[tag.name] = true;
			end
		end
		
		if tmp.type == "group" then
			local found = false;
			local roster = load_roster(origin.username, origin.host);
			local groups = roster.groups;
			if groups == nil then
				return "item-not-found";
			end
			for _,group in ipairs(groups) do
				if group == tmp.value then
					found = true;
				end
			end
			if found == false then
				return "item-not-found";
			end
		elseif tmp.type == "subscription" then
			if	tmp.value ~= "both" and
				tmp.value ~= "to" and
				tmp.value ~= "from" and
				tmp.value ~= "none" then
				return "bad-request";
			end
		end
		
		if tmp.action ~= "deny" and tmp.action ~= "allow" then
			return "bad-request";
		end
		
		list.items[#list.items + 1] = tmp;
	end
	
	table.sort(list, sortByOrder);

	privacy_lists.lists[idx] = list;
	origin.send(st.reply(stanza));
	if bare_sessions[bare_jid] ~= nil then
		iq = st.iq ( { type = "set", id="push1" } );
		iq:tag ("query", { xmlns = "jabber:iq:privacy" } );
		iq:tag ("list", { name = list.name } ):up();
		iq:up();
		for resource, session in pairs(bare_sessions[bare_jid].sessions) do
			iq.attr.to = bare_jid.."/"..resource
			session.send(iq);
		end
	end
	return true;
end

function getList(privacy_lists, origin, stanza, name)
	module:log("info", "User requests list named: %s", name or "nil");
	local ret = false;
	local reply = st.reply(stanza);
	reply:tag("query", {xmlns="jabber:iq:privacy"});

	if name == nil then
		reply:tag("active", {name=privacy_lists.active or ""}):up();
		reply:tag("default", {name=privacy_lists.default or ""}):up();
		if privacy_lists.lists then
			for _,list in ipairs(privacy_lists.lists) do
				reply:tag("list", {name=list.name}):up();
			end
			ret = true;	
		end
	else
		local idx = findNamedList(privacy_lists, name);
		module:log("debug", "list idx: %d", idx or -1);
		if idx ~= nil then
			list = privacy_lists.lists[idx];
			reply = reply:tag("list", {name=list.name});
			for _,item in ipairs(list.items) do
				reply:tag("item", {type=item.type, value=item.value, action=item.action, order=item.order});
				if item["message"] then reply:tag("message"):up(); end
				if item["iq"] then reply:tag("iq"):up(); end
				if item["presence-in"] then reply:tag("presence-in"):up(); end
				if item["presence-out"] then reply:tag("presence-out"):up(); end
				reply:up();
			end
			ret = true;
		end
	end

	if ret then
		origin.send(reply);
	end
	return ret;
end

--          "[tagname]/[target-type]/[payload-namespace]:[payload-tagname]"
module:hook("iq/bare/jabber:iq:privacy:query", function(data)
	local origin, stanza = data.origin, data.stanza;
	
	if stanza.attr.to == nil then -- only service requests to own bare JID
		local err_reply = nil;
		local query = stanza.tags[1]; -- the query element
		local valid = false;
		local privacy_lists = datamanager.load(origin.username, origin.host, "privacy") or {};

		if stanza.attr.type == "set" then
			if #query.tags >= 1 then
				for _,tag in ipairs(query.tags) do
					if tag.name == "active" or tag.name == "default" then
						if tag.attr.name == nil then -- Client declines the use of active / default list
							valid = declineList(privacy_lists, origin, stanza, tag.name);
						else -- Client requests change of active / default list
							valid = activateList(privacy_lists, origin, stanza, tag.name, tag.attr.name);
							err_reply = st.error_reply(stanza, "cancel", "item-not-found");
						end
					elseif tag.name == "list" and tag.attr.name then -- Client adds / edits a privacy list
						if #tag.tags == 0 then -- Client removes a privacy list
							valid = deleteList(privacy_lists, origin, stanza, tag.attr.name);
						else -- Client edits a privacy list
							valid = createOrReplaceList(privacy_lists, origin, stanza, tag.attr.name, tag.tags)
							if valid ~= true then
								err_reply = st.error_reply(stanza, "cancel", valid);
								valid = false;
							end
						end
					end
				end
			end
		elseif stanza.attr.type == "get" then
			local name = nil;
			local listsToRetrieve = 0;
			if #query.tags >= 1 then
				for _,tag in ipairs(query.tags) do
					if tag.name == "list" then -- Client requests a privacy list from server
						name = tag.attr.name;
						listsToRetrieve = listsToRetrieve + 1;
					end
				end
			end
			if listsToRetrieve == 0 or listsToRetrieve == 1 then
				valid = getList(privacy_lists, origin, stanza, name);
				err_reply = st.error_reply(stanza, "cancel", "item-not-found");
			end
		end

		if valid == false then
			if err_reply == nil then
				err_reply = st.error_reply(stanza, "modify", "bad-request");
			end
			origin.send(err_reply);
		else
			datamanager.store(origin.username, origin.host, "privacy", privacy_lists);
		end
		return true;
	end
	return false;
end, 500);

function checkIfNeedToBeBlocked(e, node_, host_)
	local origin, stanza = e.origin, e.stanza;
	local privacy_lists = datamanager.load(node_, host_, "privacy") or {};
	local bare_jid = node_.."@"..host_;
	
	module:log("debug", "checkIfNeedToBeBlocked: username: %s, host: %s", node_, host_);
	module:log("debug", "stanza: %s, to: %s, form: %s", stanza.name, stanza.attr.to or "nil", stanza.attr.from or "nil");
	
	if privacy_lists.lists ~= nil and stanza.attr.to ~= nil and stanza.attr.from ~= nil then
		if privacy_lists.active == nil and privacy_lists.default == nil then 
			return; -- Nothing to block, default is Allow all
		end
	
		local idx;
		local list;
		local item;
		local block = false;
		local apply = false;
		local listname = privacy_lists.active;
		if listname == nil then
			listname = privacy_lists.default; -- no active list selected, use default list
		end
		idx = findNamedList(privacy_lists, listname);
		if idx == nil then
			module:log("info", "given privacy listname not found.");
			return;
		end
		list = privacy_lists.lists[idx];
		if list == nil then
			module:log("info", "privacy list index wrong.");
			return;
		end
		for _,item in ipairs(list.items) do
			local apply = false;
			block = false;
			if	(stanza.name == "message" and item.message) or
				(stanza.name == "iq" and item.iq) or
				(stanza.name == "presence" and jid_bare(stanza.attr.to) == bare_jid and item["presence-in"]) or
				(stanza.name == "presence" and jid_bare(stanza.attr.from) == bare_jid and item["presence-out"]) or
				(item.message == false and item.iq == false and item["presence-in"] == false and item["presence-in"] == false) then
				module:log("debug", "stanza type matched.");
					apply = true;
			end
			if apply then
				local evilJid = {};
				apply = false;
				if jid_bare(stanza.attr.to) == bare_jid then
					evilJid.node, evilJid.host, evilJid.resource = jid_split(stanza.attr.from);
				else
					evilJid.node, evilJid.host, evilJid.resource = jid_split(stanza.attr.to);
				end
				if	item.type == "jid" and 
					(evilJid.node and evilJid.host and evilJid.resource and item.value == evilJid.node.."@"..evilJid.host.."/"..evilJid.resource) or
					(evilJid.node and evilJid.host and item.value == evilJid.node.."@"..evilJid.host) or
					(evilJid.host and evilJid.resource and item.value == evilJid.host.."/"..evilJid.resource) or
					(evilJid.host and item.value == evilJid.host) then
					module:log("debug", "jid matched.");
					apply = true;
					block = (item.action == "deny");
				elseif item.type == "group" then
					local roster = load_roster(node_, host_);
					local groups = roster.groups;
					for _,group in ipairs(groups) do
						if group == item.value then
							module:log("debug", "group matched.");
							apply = true;
							block = (item.action == "deny");
							break;
						end
					end
				elseif item.type == "subscription" then
					if origin.roster[jid_bare(stanza.from)].subscription == item.value then
						module:log("debug", "subscription matched.");
						apply = true;
						block = (item.action == "deny");
					end
				elseif item.type == nil then
					module:log("debug", "no item.type, so matched.");
					apply = true;
					block = (item.action == "deny");
				end
			end
			if apply then
				if block then
					module:log("info", "stanza blocked: %s, to: %s, from: %s", stanza.name, stanza.attr.to or "nil", stanza.attr.from or "nil");
					if stanza.name == "message" then
						origin.send(st.error_reply(stanza, "cancel", "service-unavailable"));
					elseif stanza.name == "iq" and (stanza.attr.type == "get" or stanza.attr.type == "set") then
						origin.send(st.error_reply(stanza, "cancel", "service-unavailable"));
					end
					return true; -- stanza blocked !
				else
					module:log("info", "stanza explicit allowed!")
				end
			end
		end
	end
	return;
end

function preCheckIncoming(e)
	if e.stanza.attr.to ~= nil then
		local node, host, resource = jid_split(e.stanza.attr.to);
		if node == nil or host == nil then
			return;
		end
		return checkIfNeedToBeBlocked(e, node, host);
	end
	return;
end

function preCheckOutgoing(e)
	if e.stanza.attr.from ~= nil then
		local node, host, resource = jid_split(e.stanza.attr.from);
		if node == nil or host == nil then
			return;
		end
		return checkIfNeedToBeBlocked(e, node, host);
	end
	return;
end


module:hook("pre-message/full", preCheckOutgoing, 500);
module:hook("pre-message/bare", preCheckOutgoing, 500);
module:hook("pre-message/host", preCheckOutgoing, 500);
module:hook("pre-iq/full", preCheckOutgoing, 500);
module:hook("pre-iq/bare", preCheckOutgoing, 500);
module:hook("pre-iq/host", preCheckOutgoing, 500);
module:hook("pre-presence/full", preCheckOutgoing, 500);
module:hook("pre-presence/bare", preCheckOutgoing, 500);
module:hook("pre-presence/host", preCheckOutgoing, 500);

module:hook("message/full", preCheckIncoming, 500);
module:hook("message/bare", preCheckIncoming, 500);
module:hook("message/host", preCheckIncoming, 500);
module:hook("iq/full", preCheckIncoming, 500);
module:hook("iq/bare", preCheckIncoming, 500);
module:hook("iq/host", preCheckIncoming, 500);
module:hook("presence/full", preCheckIncoming, 500);
module:hook("presence/bare", preCheckIncoming, 500);
module:hook("presence/host", preCheckIncoming, 500);

-- helpers.log_events(hosts["albastru.de"].events, "albastru.de");
-- helpers.log_events(prosody.events, "*");

module:log("info", "mod_privacy loaded ...");
