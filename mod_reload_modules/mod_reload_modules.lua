local array, it, set = require "util.array", require "util.iterators", require "util.set";
local mm = require "core.modulemanager";

function reload_all()
	local modules = module:get_option_set("reload_modules", {});
	if not modules then
		module:log("warn", "No modules listed in the config to reload - set reload_modules to a list");
		return;
	end
	local configured_modules = module:get_option_inherited_set("modules_enabled", {});
	local loaded_modules = set.new(array.collect(it.keys(prosody.hosts[module.host].modules)));
	local need_to_load = set.intersection(configured_modules - loaded_modules, modules);
	local need_to_unload = set.intersection(loaded_modules - configured_modules, modules);

	for module_name in need_to_load do
		module:log("debug", "Loading %s", module_name);
		mm.load(module.host, module_name);
	end

	for module_name in need_to_unload do
		module:log("debug", "Unloading %s", module_name);
		mm.unload(module.host, module_name);
	end

	modules:exclude(need_to_load+need_to_unload)

	for module_name in set.intersection(modules,configured_modules) do
		module:log("debug", "Reloading %s", module_name);
		mm.reload(module.host, module_name);
	end
end


if module.hook_global then
	module:hook_global("config-reloaded", reload_all);
else -- COMPAT w/pre-0.9
	function module.load()
		prosody.events.add_handler("config-reloaded", reload_all);
	end
	function module.unload()
		prosody.events.remove_handler("config-reloaded", reload_all);
	end
end
