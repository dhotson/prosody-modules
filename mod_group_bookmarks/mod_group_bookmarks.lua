-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local st = require "util.stanza"

local datamanager = require "util.datamanager"
local jid, datamanager = require "util.jid", require "util.datamanager";
local jid_bare, jid_prep, jid_split = jid.bare, jid.prep, jid.split;

local module_host = module:get_host();

local rooms;
local members;

local bookmarks_file;

module:add_feature("jabber:iq:private");

function inject_bookmarks(username, host, data)
	local jid = username.."@"..host;
	data:reset();
	if members[jid] then
		for _, room in ipairs(members[jid]) do
			data:tag("conference", {
				name = room;
				jid = room;
				autojoin = "1";
			});
			local nick = rooms[room][jid];
			if nick then
				data:tag("nick"):text(nick):up();
			end
			data:up();
		end
	end
	return data;
end

module:hook("iq/self/jabber:iq:private:query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local type = stanza.attr.type;
	local query = stanza.tags[1];
	if #query.tags == 1 then
		local tag = query.tags[1];
		local key = tag.name..":"..tag.attr.xmlns;
		local data, err = datamanager.load(origin.username, origin.host, "private");
		if err then
			origin.send(st.error_reply(stanza, "wait", "internal-server-error"));
			return true;
		end
		if stanza.attr.type == "get" then
			local data = data and data[key];
			if (not data) and key == "storage:storage:bookmarks" then
				data = st.stanza("storage", { xmlns = "storage:bookmarks" });
			end
			if data then
				data = st.deserialize(data);
				if key == "storage:storage:bookmarks" then
					data = inject_bookmarks(origin.username, origin.host, data);
				end
				origin.send(st.reply(stanza):tag("query", {xmlns = "jabber:iq:private"})
					:add_child(data));
			else
				origin.send(st.reply(stanza):add_child(stanza.tags[1]));
			end
			return true;
		end
	end
end, 1);

function module.load()
	bookmarks_file = module:get_option_string("group_bookmarks_file");

	rooms = { default = {} };
	members = { };

	if not bookmarks_file then
		module:log("error", "Please specify group_bookmarks_file in your configuration");
		return;
	end
	
	local curr_room;
	for line in io.lines(bookmarks_file) do
		if line:match("^%s*%[.-%]%s*$") then
			curr_room = line:match("^%s*%[(.-)%]%s*$");
			if curr_room:match("^%+") then
				curr_room = curr_room:gsub("^%+", "");
				if not members[false] then
					members[false] = {};
				end
				members[false][#members[false]+1] = curr_room; -- Is a public group
			end
			module:log("debug", "New group: %s", tostring(curr_room));
			rooms[curr_room] = rooms[curr_room] or {};
		elseif curr_room then
			-- Add JID
			local entryjid, name = line:match("([^=]*)=?(.*)");
			module:log("debug", "entryjid = '%s', name = '%s'", entryjid, name);
			local jid;
			jid = jid_prep(entryjid:match("%S+"));
			if jid then
				module:log("debug", "New member of %s: %s", tostring(curr_room), tostring(jid));
				rooms[curr_room][jid] = name or false;
				members[jid] = members[jid] or {};
				members[jid][#members[jid]+1] = curr_room;
			end
		end
	end
	module:log("info", "Group bookmarks loaded successfully");
end

