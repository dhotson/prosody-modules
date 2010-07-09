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

-- TODO: Allow reloading multiple modules (depends on list-multi
function reload_modules_handler(self, data, state)
	local modules = {};
	local layout = dataforms_new {
		title = "Reload module";
		instructions = "Select the module to be reloaded";

		{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/protocol/modules#reload" };
		{ name = "module", type = "list-single", value = modules, label = "Module to be reloaded:"};
	};
	if state then
		if data.action == "cancel" then
			return { status = "canceled" };
		end
		fields = layout:data(data.form);
		local ok, err = modulemanager.reload(data.to, fields.module);
		if ok then
			return { status = "completed", info = 'Module "'..fields.module..'" successfully reloaded on host "'..data.to..'".' };
		else
			return { status = "completed", error = 'Failed to reload module "'..fields.module..'" on host "'..data.to..
			'". Error was: "'..tostring(err)..'"' };
		end
	else
		local modules2 = array.collect(keys(hosts[data.to].modules)):sort();
		for i, val in ipairs(modules2) do
			modules[i] = val;
		end
		return { status = "executing", form = layout }, "executing";
	end
end

local list_modules_desc = adhoc_new("List loaded modules", "http://prosody.im/protocol/modules#list", list_modules_handler, "admin");
local reload_modules_desc = adhoc_new("Reload module", "http://prosody.im/protocol/modules#reload", reload_modules_handler, "admin");

module:add_item("adhoc", list_modules_desc);
module:add_item("adhoc", reload_modules_desc);
