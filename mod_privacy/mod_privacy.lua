-- Prosody IM
-- Copyright (C) 2008-2009 Matthew Wild
-- Copyright (C) 2008-2009 Waqas Hussain
-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local prosody = prosody;
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
		module:log("debug", "privacy_lists.list is nil. no lists loaded.")
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

function isListUsed(origin, name, privacy_lists)	
	if bare_sessions[origin.username.."@"..origin.host].sessions ~= nil then
		for resource, session in pairs(bare_sessions[origin.username.."@"..origin.host].sessions) do
			if resource ~= origin.resource then
				if session.activePrivacyList == name then
					module:log("debug", "List {0} is in use.", name);
					return true;
				elseif session.activePrivacyList == nil and privacy_lists.default == name then
					module:log("debug", "List {0} is in use.", name);
					return true;
				end
			end
		end
	end
	module:log("debug", "List {0} is in NOT use.", name);
	return false;
end

function isAnotherSessionUsingDefaultList(origin)
	local ret = false
	if bare_sessions[origin.username.."@"..origin.host].sessions ~= nil then
		for resource, session in pairs(bare_sessions[origin.username.."@"..origin.host].sessions) do
			if resource ~= origin.resource and session.activePrivacyList == nil then
				module:log("debug", "Default list is used by another resource.");
				ret = true;
				break;
			end
		end
	end
	return ret;
end

function declineList (privacy_lists, origin, stanza, which)
	module:log("info", "User requests to decline the use of privacy list: %s", which);
	if which == "default" then
		if isAnotherSessionUsingDefaultList(origin) then
			return { "cancel", "conflict", "Another session is online and using the default list."};
		end
		privacy_lists.default = nil;
		origin.send(st.reply(stanza));
	elseif which == "active" then
		origin.activePrivacyList = nil;
		origin.send(st.reply(stanza));
	else
		return {"modify", "bad-request", "Neither default nor active list specifed to decline."};
	end
	return true;
end

function activateList (privacy_lists, origin, stanza, which, name)
	module:log("info", "User requests to change the privacy list: %s, to be list named %s", which, name);
	local idx = findNamedList(privacy_lists, name);

	if privacy_lists.default == nil then
		privacy_lists.default = "";
	end
	if origin.activePrivacyList == nil then
		origin.activePrivacyList = "";
	end
	
	if which == "default" and idx ~= nil then
		if isAnotherSessionUsingDefaultList(origin) then
			return {"cancel", "conflict", "Another session is online and using the default list."};
		end
		privacy_lists.default = name;
		origin.send(st.reply(stanza));
	elseif which == "active" and idx ~= nil then
		origin.activePrivacyList = name;
		origin.send(st.reply(stanza));
	else
		return {"modify", "bad-request", "Either not active or default given or unknown list name specified."};
	end
	return true;
end

function deleteList (privacy_lists, origin, stanza, name)
	module:log("info", "User requests to delete privacy list: %s", name);
	local idx = findNamedList(privacy_lists, name);

	if idx ~= nil then
		if isListUsed(origin, name, privacy_lists) then
			return {"cancel", "conflict", "Another session is online and using the list which should be deleted."};
		end
		if privacy_lists.default == name then
			privacy_lists.default = "";
		end
		if origin.activePrivacyList == name then
			origin.activePrivacyList = "";
		end
		table.remove(privacy_lists.lists, idx);
		origin.send(st.reply(stanza));
		return true;
	end
	return {"modify", "bad-request", "Not existing list specifed to be deleted."};
end

local function sortByOrder(a, b)
	if a.order < b.order then
		return true;
	end
	return false;
end

function createOrReplaceList (privacy_lists, origin, stanza, name, entries, roster)
	module:log("info", "User requests to create / replace list named %s, item count: %d", name, #entries);
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
			return {"modify", "bad-request", "Order attribute not valid."};
		end
		
		if item.attr.type ~= nil and item.attr.type ~= "jid" and item.attr.type ~= "subscription" and item.attr.type ~= "group" then
			return {"modify", "bad-request", "Type attribute not valid."};
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
			for jid,item in pairs(roster) do
				if item.groups ~= nil then
					for group in pairs(item.groups) do
						if group == tmp.value then
							found = true;
							break;
						end
					end
					if found == true then
						break;
					end
				end
			end
			if found == false then
				return {"cancel", "item-not-found", "Specifed roster group not existing."};
			end
		elseif tmp.type == "subscription" then
			if	tmp.value ~= "both" and
				tmp.value ~= "to" and
				tmp.value ~= "from" and
				tmp.value ~= "none" then
				return {"cancel", "bad-request", "Subscription value must be both, to, from or none."};
			end
		end
		
		if tmp.action ~= "deny" and tmp.action ~= "allow" then
			return {"cancel", "bad-request", "Action must be either deny or allow."};
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
	else
		return {"cancel", "bad-request", "internal error."};
	end
	return true;
end

function getList(privacy_lists, origin, stanza, name)
	module:log("info", "User requests list named: %s", name or "nil");
	local reply = st.reply(stanza);
	reply:tag("query", {xmlns="jabber:iq:privacy"});

	if name == nil then
		reply:tag("active", {name=origin.activePrivacyList or ""}):up();
		reply:tag("default", {name=privacy_lists.default or ""}):up();
		if privacy_lists.lists then
			for _,list in ipairs(privacy_lists.lists) do
				reply:tag("list", {name=list.name}):up();
			end
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
		else
			return {"cancel", "item-not-found", "Unknown list specified."};
		end
	end
	
	origin.send(reply);
	return true;
end

module:hook("iq/bare/jabber:iq:privacy:query", function(data)
	local origin, stanza = data.origin, data.stanza;
	
	if stanza.attr.to == nil then -- only service requests to own bare JID
		local query = stanza.tags[1]; -- the query element
		local valid = false;
		local privacy_lists = datamanager.load(origin.username, origin.host, "privacy") or {};

		if stanza.attr.type == "set" then
			if #query.tags == 1 then --  the <query/> element MUST NOT include more than one child element 
				for _,tag in ipairs(query.tags) do
					if tag.name == "active" or tag.name == "default" then
						if tag.attr.name == nil then -- Client declines the use of active / default list
							valid = declineList(privacy_lists, origin, stanza, tag.name);
						else -- Client requests change of active / default list
							valid = activateList(privacy_lists, origin, stanza, tag.name, tag.attr.name);
						end
					elseif tag.name == "list" and tag.attr.name then -- Client adds / edits a privacy list
						if #tag.tags == 0 then -- Client removes a privacy list
							valid = deleteList(privacy_lists, origin, stanza, tag.attr.name);
						else -- Client edits a privacy list
							valid = createOrReplaceList(privacy_lists, origin, stanza, tag.attr.name, tag.tags);  -- TODO check if used!
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
			end
		end

		if valid ~= true then
			if valid[0] == nil then
				valid[0] = "cancel";
			end
			if valid[1] == nil then
				valid[1] = "bad-request";
			end
			origin.send(st.error_reply(stanza, valid[0], valid[1], valid[2]));
		else
			datamanager.store(origin.username, origin.host, "privacy", privacy_lists);
		end
		return true;
	end
	return false;
end, 500);

function checkIfNeedToBeBlocked(e, session)
	local origin, stanza = e.origin, e.stanza;
	local privacy_lists = datamanager.load(session.username, session.host, "privacy") or {};
	local bare_jid = session.username.."@"..session.host;

	module:log("debug", "checkIfNeedToBeBlocked: username: %s, host: %s", session.username, session.host);
	module:log("debug", "stanza: %s, to: %s, form: %s", stanza.name, stanza.attr.to or "nil", stanza.attr.from or "nil");
	
	if stanza.attr.to ~= nil and stanza.attr.from ~= nil then
		module:log("debug", "privacy_lists.lists: %s", tostring(privacy_lists.lists));
		module:log("debug", "session.activePrivacyList: %s", tostring(session.activePrivacyList));
		module:log("debug", "privacy_lists.default: %s", tostring(privacy_lists.default));
		if privacy_lists.lists == nil or
		   (session.activePrivacyList == nil or session.activePrivacyList == "") and
		   (privacy_lists.default == nil     or privacy_lists.default == "")
		then 
			module:log("debug", "neither active nor default list set (both are nil) or privacy_lists totally nil. So nothing to do => default is Allow All.");
			return; -- Nothing to block, default is Allow all
		end
	    if jid_bare(stanza.attr.from) == bare_jid and jid_bare(stanza.attr.to) == bare_jid then
            module:log("debug", "Never block communications from one of a user's resources to another.");
            return; -- from one of a user's resource to another => HANDS OFF!
        end 
    
		local idx;
		local list;
		local item;
		local listname = session.activePrivacyList;
		if listname == nil or listname == "" then
			listname = privacy_lists.default; -- no active list selected, use default list
		end
		idx = findNamedList(privacy_lists, listname);
		if idx == nil then
			module:log("error", "given privacy listname not found. name: %s", listname);
			return;
		end
		list = privacy_lists.lists[idx];
		if list == nil then
			module:log("info", "privacy list index wrong. index: %d", idx);
			return;
		end
		for _,item in ipairs(list.items) do
			local apply = false;
			local block = false;
			if	(stanza.name == "message" and item.message) then
				module:log("debug", "message stanza match.");
				apply = true;
			elseif (stanza.name == "iq" and item.iq) then
				module:log("debug", "iq stanza match!");
				apply = true;
			elseif (stanza.name == "presence" and jid_bare(stanza.attr.to) == bare_jid and item["presence-in"]) then
				module:log("debug", "presence-in stanza match.");
				apply = true;
			elseif (stanza.name == "presence" and jid_bare(stanza.attr.from) == bare_jid and item["presence-out"]) then
				module:log("debug", "presence-out stanza match");
				apply = true;
			elseif (item.message == false and item.iq == false and item["presence-in"] == false and item["presence-in"] == false) then
				module:log("debug", "all is false, so apply.");
				apply = true;
			end
			if apply then
				local evilJid = {};
				apply = false;
				if jid_bare(stanza.attr.to) == bare_jid then
					module:log("debug", "evil jid is (from): %s", stanza.attr.from);
					evilJid.node, evilJid.host, evilJid.resource = jid_split(stanza.attr.from);
				else
					module:log("debug", "evil jid is (to): %s", stanza.attr.to);
					evilJid.node, evilJid.host, evilJid.resource = jid_split(stanza.attr.to);
				end
				module:log("debug", "Item Type: %s", tostring(item.type));
				module:log("debug", "Item Action: %s", item.action);
				if	item.type == "jid" and 
					(evilJid.node and evilJid.host and evilJid.resource and item.value == evilJid.node.."@"..evilJid.host.."/"..evilJid.resource) or
					(evilJid.node and evilJid.host and item.value == evilJid.node.."@"..evilJid.host) or
					(evilJid.host and evilJid.resource and item.value == evilJid.host.."/"..evilJid.resource) or
					(evilJid.host and item.value == evilJid.host) then
					module:log("debug", "jid matched.");
					apply = true;
					block = (item.action == "deny");
				elseif item.type == "group" then
					local roster = load_roster(session.username, session.host);
					local groups = roster[evilJid.node .. "@" .. evilJid.host].groups;
					for group in pairs(groups) do
						if group == item.value then
							module:log("debug", "group matched.");
							apply = true;
							block = (item.action == "deny");
							break;
						end
					end
				elseif item.type == "subscription" and evilJid.node ~= nil and evilJid.host ~= nil then -- we need a valid bare evil jid
					local roster = load_roster(session.username, session.host);
					if roster[evilJid.node .. "@" .. evilJid.host].subscription == item.value then
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
					return;
				end
			end
		end
	end
	return;
end

function preCheckIncoming(e)
	local session;
	if e.stanza.attr.to ~= nil then
		local node, host, resource = jid_split(e.stanza.attr.to);
		if node == nil or host == nil then
			return;
		end
		if resource == nil then
			local prio = 0;
			local session_;
			if bare_sessions[node.."@"..host] ~= nil then
				for resource, session_ in pairs(bare_sessions[node.."@"..host].sessions) do
					if session_.priority > prio then
						session = session_;
						prio = session_.priority;
					end
				end
			end
		else
			session = full_sessions[node.."@"..host.."/"..resource];
		end
		if session ~= nil then
			return checkIfNeedToBeBlocked(e, session);
		else
			module:log("debug", "preCheckIncoming: Couldn't get session for jid: %s@%s/%s", node or "nil", host or "nil", resource or "nil")
		end
	end
	return;
end

function preCheckOutgoing(e)
	local session = e.origin;
	if e.stanza.attr.from == nil then
		e.stanza.attr.form = session.username .. "@" .. session.host;
		if session.resource ~= nil then
		 	e.stanza.attr.from = e.stanza.attr.form .. "/" .. session.resource;
		end
	end
	return checkIfNeedToBeBlocked(e, session);
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

module:log("info", "mod_privacy loaded ...");
