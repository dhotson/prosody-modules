local mm = require "core.modulemanager";

local function reload_module(name)
	local ok, err = mm.reload(module.host, name);
	if ok then
		module:log("debug", "Reloaded %s", name);
	else
		module:log("error", "Failed to reload %s: %s", name, err);
	end
end

prosody.events.add_handler("config-reloaded", function ()
	local modules = module:get_option_array("reload_modules");
	if not modules then
		module:log("warn", "No modules listed in the config to reload - set reload_modules to a list");
		return;
	end
	for _, module in ipairs(modules) do
		reload_module(module);
	end
end);
