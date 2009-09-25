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
local privacy_lists = nil
local bare_sessions = bare_sessions;


function findNamedList (name)
	local ret = nil
	if privacy_lists.lists == nil then return nil; end

	for i=1, #privacy_lists.lists do
		if privacy_lists.lists[i].name == name then
			ret = i;
			break;
		end
	end
	return ret;
end

function declineList (origin, stanza, which)
	module:log("info", "User requests to decline the use of privacy list: %s", which);
	privacy_lists[which] = nil;
	origin.send(st.reply(stanza));
	return true;
end

function activateList (origin, stanza, which, name)
	module:log("info", "User requests to change the privacy list: %s, to be list named %s", which, name);
	local ret = false;
	local idx = findNamedList(name);

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

function deleteList (origin, stanza, name)
	module:log("info", "User requests to delete privacy list: %s", name);
	local ret = false;
	local idx = findNamedList(name);

	if idx ~= nil then
		table.remove(privacy_lists.lists, idx);
		origin.send(st.reply(stanza));
		ret = true;
	end
	return ret;
end

function createOrReplaceList (origin, stanza, name, entries)
	module:log("info", "User requests to create / replace list named %s, item count: %d", name, #entries);
	local ret = true;
	local idx = findNamedList(name);
	local bare_jid = origin.username.."@"..origin.host;
	
	if privacy_lists.lists == nil then
		privacy_lists.lists = {};
	end

	if idx == nil then
		idx = #privacy_lists.lists + 1;
	end

	local list = {};
	list.name = name;
	list.items = {};

	for _,item in ipairs(entries) do
		tmp = {};
		tmp["type"] = item.attr.type;
		tmp["value"] = item.attr.value;
		tmp["action"] = item.attr.action;
		tmp["order"] = item.attr.order;
		tmp["presence-in"] = false;
		tmp["presence-out"] = false;
		tmp["message"] = false;
		tmp["iq"] = false;
		
		if #item.tags > 0 then
			for _,tag in ipairs(item.tags) do
				tmp[tag.name] = true;
			end
		end
		list.items[#list.items + 1] = tmp;
	end

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

function getList(origin, stanza, name)
	module:log("info", "User requests list named: %s", name or "nil");
	local ret = true;
	local idx = findNamedList(name);
	local reply = st.reply(stanza);
	reply = reply:tag("query", {xmlns="jabber:iq:privacy"});

	if idx == nil then
		reply:tag("active", {name=privacy_lists.active or ""}):up();
		reply:tag("default", {name=privacy_lists.default or ""}):up();
		if privacy_lists.lists then
			for _,list in ipairs(privacy_lists.lists) do
				reply:tag("list", {name=list.name}):up();
			end		
		end
	else
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
	end
	
	origin.send(reply);
	return ret;
end

--          "[tagname]/[target-type]/[payload-namespace]:[payload-tagname]"
module:hook("iq/bare/jabber:iq:privacy:query", function(data)
	local origin, stanza = data.origin, data.stanza;
	
	if stanza.attr.to == nil then -- only service requests to own bare JID
		local query = stanza.tags[1]; -- the query element
		local valid = false;
		privacy_lists = datamanager.load(origin.username, origin.host, "privacy") or {};

		if stanza.attr.type == "set" then
			if #query.tags >= 1 then
				for _,tag in ipairs(query.tags) do
					if tag.name == "active" or tag.name == "default" then
						if tag.attr.name == nil then -- Client declines the use of active / default list
							valid = declineList(origin, stanza, tag.name);
						else -- Client requests change of active / default list
							valid = activateList(origin, stanza, tag.name, tag.attr.name);
						end
					elseif tag.name == "list" and tag.attr.name then -- Client adds / edits a privacy list
						if #tag.tags == 0 then -- Client removes a privacy list
							valid = deleteList(origin, stanza, tag.attr.name);
						else -- Client edits a privacy list
							valid = createOrReplaceList(origin, stanza, tag.attr.name, tag.tags)
						end
					end
				end
			end
		elseif stanza.attr.type == "get" then
			local name = nil;
			if #query.tags >= 1 then
				for _,tag in ipairs(query.tags) do
					if tag.name == "list" then -- Client requests a privacy list from server
						name = tag.attr.name;
						break;
					end
				end
			end
			valid = getList(origin, stanza, name);
		end

		if valid == false then
			origin.send(st.error_reply(stanza, "modify", "bad-request"));
		else
			datamanager.store(origin.username, origin.host, "privacy", privacy_lists);
		end
		return true;
	end
	return false;
end, 500);

function checkIfNeedToBeBlocked(e)
	return false;
end

module:hook("pre-message/full", checkIfNeedToBeBlocked, 500);
module:hook("pre-iq/bare", checkIfNeedToBeBlocked, 500);
module:hook("pre-presence/bare", checkIfNeedToBeBlocked, 500);

-- helpers.log_events(hosts["albastru.de"].events, "albastru.de");
-- helpers.log_events(prosody.events, "*");

module:log("info", "mod_privacy loaded ...");
