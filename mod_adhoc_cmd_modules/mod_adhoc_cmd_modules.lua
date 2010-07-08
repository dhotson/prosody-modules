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
local adhoc_new = module:require "adhoc".new;

function list_modules_handler(self, data, state)
	local list_modules_result = dataforms_new {
		title = "List of loaded modules";

		{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/protocol/modules#list" };
		{ name = "modules", type = "text-multi", label = "The following modules are loaded:" };
	};

	local modules = array.collect(keys(hosts[data.to].modules)):sort()
	local modules_str = nil;
	for _, name in ipairs(modules) do
		modules_str = ((modules_str and modules_str .. "\n") or "") .. name;
	end

	return { status = "completed", result = { layout = list_modules_result; data = { modules = modules_str } } };
end

local list_modules_desc = adhoc_new("List loaded modules", "http://prosody.im/protocol/modules#list", list_modules_handler, "admin");

module:add_item("adhoc", list_modules_desc);
