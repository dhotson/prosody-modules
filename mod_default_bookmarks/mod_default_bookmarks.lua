-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- Copyright (C) 2011 Kim Alvefur
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local st = require "util.stanza"

local dm_load = require "util.datamanager".load
local jid_split = require "util.jid".split

local private_bookmarks_ns = "storage:storage:bookmarks";

local bookmarks = module:get_option("default_bookmarks");

module:hook("iq-get/self/jabber:iq:private:query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local from = stanza.attr.from;
	if not stanza.tags[1]:get_child("storage", "storage:bookmarks") then return end
	local data, err = dm_load(origin.username, origin.host, "private");
	if data and data[private_bookmarks_ns] then return end

	local reply = st.reply(stanza):tag("query", {xmlns = "jabber:iq:private"})
		:tag("storage", { xmlns = "storage:bookmarks" });

	local nick = jid_split(from);

	local bookmark;
	for i=1,#bookmarks do
		bookmark = bookmarks[i];
		if type(bookmark) ~= "table" then -- assume it's only a jid
			bookmark = { jid = bookmark, name = jid_split(bookmark) };
		end
		reply:tag("conference", {
			jid = bookmark.jid,
			name = bookmark.name,
			autojoin = "1",
		}):tag("nick"):text(nick):up():up();
	end
	origin.send(reply);
	return true;
end, 1);
