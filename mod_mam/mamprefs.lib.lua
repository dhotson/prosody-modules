-- XEP-0313: Message Archive Management for Prosody
-- Copyright (C) 2011-2012 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local host = module.host;

local dm_load = require "util.datamanager".load;
local dm_store = require "util.datamanager".store;

local global_default_policy = module:get_option("default_archive_policy", false);

do
	local prefs_format = {
		[false] = "roster",
		-- default ::= true | false | "roster"
		-- true = always, false = never, nil = global default
		["romeo@montague.net"] = true, -- always
		["montague@montague.net"] = false, -- newer
	};
end

local prefs_store = "archive2_prefs";
local function get_prefs(user)
	return dm_load(user, host, prefs_store) or
		{ [false] = global_default_policy };
end
local function set_prefs(user, prefs)
	return dm_store(user, host, prefs_store, prefs);
end

return {
	get = get_prefs,
	set = set_prefs,
}
