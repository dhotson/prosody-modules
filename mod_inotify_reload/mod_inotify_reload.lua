-- mod_inotify_reload
-- Reloads modules when their files change
-- Depends on linotify: https://github.com/hoelzro/linotify

module:set_global();

local inotify = require "inotify";
local modulemanager = require "core.modulemanager";

local inh = inotify.init();

local watches = {};
local watch_ids = {};

-- Fake socket object around inotify
local inh_conn = {
	getfd = function () return inh:fileno(); end;
	dirty = function (self) return false; end;
	settimeout = function () end;
	send = function (_, d) return #d, 0; end;
	close = function () end;
	receive = function ()
		local events = inh:read();
		for _, event in ipairs(events) do
			local mod = watches[watch_ids[event.wd]];
			if mod then
				local host, name = mod.host, mod.name;
				module:log("debug", "Reloading changed module mod_%s on %s", name, host);
				modulemanager.reload(host, name);
			else
				module:log("warn", "no watch for %d", event.wd);
			end
		end
		return "";
	end
};
require "net.server".wrapclient(inh_conn, "inotify", inh:fileno(), {
	onincoming = function () end, ondisconnect = function () end
}, "*a");

function watch_module(name, host, path)
	local id, err = inh:addwatch(path, inotify.IN_CLOSE_WRITE);
	if not id then return nil, err; end
	local k = host.."\0"..name;
	watches[k] = { id = id, path = path, name = name, host = host };
	watch_ids[id] = k;
	return true;
end

function unwatch_module(name, host)
	local k = host.."\0"..name;
	if not watches[k] then
		return nil, "not-watching";
	end
	local id = watches[k].id;
	local ok, err = inh:rmwatch(id);
	watches[k] = nil;
	watch_ids[id] = nil;
	return ok, err;
end

function module_loaded(event)
	local host, name = event.host, event.module;
	local path = modulemanager.get_module(host, name).module.path;
	if not path then
		module:log("warn", "Couldn't watch mod_%s, no path", name);
		return;
	end
	if watch_module(name, host, path) then
		module:log("debug", "Watching mod_%s", name);
	end
end

function module_unloaded(event)
	unwatch_module(event.module, event.host);
end

function module.add_host(module)
	module:hook("module-loaded", module_loaded);
	module:hook("module-unloaded", module_unloaded);
end

module:hook("module-loaded", module_loaded);
module:hook("module-unloaded", module_unloaded);

