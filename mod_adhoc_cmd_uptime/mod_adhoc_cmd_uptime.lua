-- Copyright (C) 2009 Florian Zeitz
-- 
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local _G = _G;
local prosody = _G.prosody;
local st, uuid = require "util.stanza", require "util.uuid";
local adhoc_new = module:require "adhoc".new;

function uptime()
	local t = os.time()-prosody.start_time;
	local seconds = t%60;
	t = (t - seconds)/60;
	local minutes = t%60;
	t = (t - minutes)/60;
	local hours = t%24;
	t = (t - hours)/24;
	local days = t;
	return string.format("This server has been running for %d day%s, %d hour%s and %d minute%s (since %s)", 
		days, (days ~= 1 and "s") or "", hours, (hours ~= 1 and "s") or "", 
		minutes, (minutes ~= 1 and "s") or "", os.date("%c", prosody.start_time));
end

function uptime_command_handler (item, origin, stanza)
	origin.send(st.reply(stanza):add_child(item:cmdtag("completed", uuid.generate()):tag("note", {type="info"}):text(uptime())));
	return true;
end

local descriptor = adhoc_new("Get uptime", "uptime", uptime_command_handler);

module:add_item ("adhoc", descriptor);

