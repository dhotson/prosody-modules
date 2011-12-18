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

module:hook("iq/self/jabber:iq:private:query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local typ = stanza.attr.type;
	local from = stanza.attr.from;
	local query = stanza.tags[1];
	if #query.tags == 1 and typ == "get" then
		local tag = query.tags[1];
		local key = tag.name..":"..tag.attr.xmlns;
		if key == "storage:storage:bookmarks" then
			local data, err = dm_load(origin.username, origin.host, "private");
			if not(data and data[key]) then
				local bookmarks = module:get_option("default_bookmarks");
				if bookmarks and #bookmarks > 0 then
					local reply = st.reply(stanza):tag("query", {xmlns = "jabber:iq:private"})
						:tag("storage", { xmlns = "storage:bookmarks" });
					local nick = jid_split(from);
					for i=1,#bookmarks do
						local bookmark = bookmarks[i];
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
				end
			end
		end
	end
end, 1);
