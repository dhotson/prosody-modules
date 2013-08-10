-- XEP-0313: Message Archive Management for Prosody
-- Copyright (C) 2011-2013 Kim Alvefur
--
-- This file is MIT/X11 licensed.

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

local prefs = module:open_store("archive2_prefs");
local function get_prefs(user)
	return prefs:get(user) or { [false] = global_default_policy };
end
local function set_prefs(user, user_prefs)
	return prefs:set(user, user_prefs);
end

return {
	get = get_prefs,
	set = set_prefs,
}
