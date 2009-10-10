-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza";
local adhoc_new = module:require "adhoc".new;

function ping_command_handler (item, origin, stanza)
	local now = os.date("%Y-%m-%dT%X");
	origin.send(st.reply(stanza):add_child(item:cmdtag("completed", now):tag("note", {type="info"}):text("Pong\n" .. now)));
	return true;
end

local descriptor = adhoc_new("Ping", "ping", ping_command_handler);

function module.unload()
	module:remove_item("adhoc", descriptor);
end

module:add_item ("adhoc", descriptor);

