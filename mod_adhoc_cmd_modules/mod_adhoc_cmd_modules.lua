-- Copyright (C) 2009-2010 Florian Zeitz
--
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local _G = _G;

local prosody = _G.prosody;
local hosts = prosody.hosts;

require "util.iterators";
local dataforms_new = require "util.dataforms".new;
local array = require "util.array";
local modulemanager = require "modulemanager";
local adhoc_new = module:require "adhoc".new;

function list_modules_handler(self, data, state)
	local result = dataforms_new {
		title = "List of loaded modules";

		{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/protocol/modules#list" };
		{ name = "modules", type = "text-multi", label = "The following modules are loaded:" };
	};

	local modules = array.collect(keys(hosts[data.to].modules)):sort():concat("\n");

	return { status = "completed", result = { layout = result; data = { modules = modules } } };
end

function load_module_handler(self, data, state)
	local layout = dataforms_new {
		title = "Load module";
		instructions = "Specify the module to be loaded";

		{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/protocol/modules#load" };
		{ name = "module", type = "text-single", required = true, label = "Module to be loaded:"};
	};
	if state then
		if data.action == "cancel" then
			return { status = "canceled" };
		end
		local fields = layout:data(data.form);
		if (not fields.module) or (fields.module == "") then
			return { status = "completed", error = {
				message = "Please specify a module. (This means your client misbehaved, as this field is required)"
			} };
		end
		if modulemanager.is_loaded(data.to, fields.module) then
			return { status = "completed", info = "Module already loaded" };
		end
		local ok, err = modulemanager.load(data.to, fields.module);
		if ok then
			return { status = "completed", info = 'Module "'..fields.module..'" successfully loaded on host "'..data.to..'".' };
		else
			return { status = "completed", error = { message = 'Failed to load module "'..fields.module..'" on host "'..data.to..
			'". Error was: "'..tostring(err or "<unspecified>")..'"' } };
		end
	else
		local modules = array.collect(keys(hosts[data.to].modules)):sort();
		return { status = "executing", form = layout }, "executing";
	end
end

-- TODO: Allow reloading multiple modules (depends on list-multi)
function reload_modules_handler(self, data, state)
	local layout = dataforms_new {
		title = "Reload module";
		instructions = "Select the module to be reloaded";

		{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/protocol/modules#reload" };
		{ name = "module", type = "list-single", required = true, label = "Module to be reloaded:"};
	};
	if state then
		if data.action == "cancel" then
			return { status = "canceled" };
		end
		local fields = layout:data(data.form);
		if (not fields.module) or (fields.module == "") then
			return { status = "completed", error = {
				message = "Please specify a module. (This means your client misbehaved, as this field is required)"
			} };
		end
		local ok, err = modulemanager.reload(data.to, fields.module);
		if ok then
			return { status = "completed", info = 'Module "'..fields.module..'" successfully reloaded on host "'..data.to..'".' };
		else
			return { status = "completed", error = { message = 'Failed to reload module "'..fields.module..'" on host "'..data.to..
			'". Error was: "'..tostring(err)..'"' } };
		end
	else
		local modules = array.collect(keys(hosts[data.to].modules)):sort();
		return { status = "executing", form = { layout = layout; data = { module = modules } } }, "executing";
	end
end

-- TODO: Allow unloading multiple modules (depends on list-multi)
function unload_modules_handler(self, data, state)
	local layout = dataforms_new {
		title = "Unload module";
		instructions = "Select the module to be unloaded";

		{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/protocol/modules#unload" };
		{ name = "module", type = "list-single", required = true, label = "Module to be unloaded:"};
	};
	if state then
		if data.action == "cancel" then
			return { status = "canceled" };
		end
		local fields = layout:data(data.form);
		if (not fields.module) or (fields.module == "") then
			return { status = "completed", error = {
				message = "Please specify a module. (This means your client misbehaved, as this field is required)"
			} };
		end
		local ok, err = modulemanager.unload(data.to, fields.module);
		if ok then
			return { status = "completed", info = 'Module "'..fields.module..'" successfully unloaded on host "'..data.to..'".' };
		else
			return { status = "completed", error = { message = 'Failed to unload module "'..fields.module..'" on host "'..data.to..
			'". Error was: "'..tostring(err)..'"' } };
		end
	else
		local modules = array.collect(keys(hosts[data.to].modules)):sort();
		return { status = "executing", form = { layout = layout; data = { module = modules } } }, "executing";
	end
end

local list_modules_desc = adhoc_new("List loaded modules", "http://prosody.im/protocol/modules#list", list_modules_handler, "admin");
local load_module_desc = adhoc_new("Load module", "http://prosody.im/protocol/modules#load", load_module_handler, "admin");
local reload_modules_desc = adhoc_new("Reload module", "http://prosody.im/protocol/modules#reload", reload_modules_handler, "admin");
local unload_modules_desc = adhoc_new("Unload module", "http://prosody.im/protocol/modules#unload", unload_modules_handler, "admin");

module:add_item("adhoc", list_modules_desc);
module:add_item("adhoc", load_module_desc);
module:add_item("adhoc", reload_modules_desc);
module:add_item("adhoc", unload_modules_desc);
