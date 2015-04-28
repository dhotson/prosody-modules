module:set_global();

local tostring = tostring;
local filters = require "util.filters";

local def_env = module:shared("admin_telnet/env");
local rawdebug_enabled = module:shared("sessions");
local full_sessions = prosody.full_sessions;
local log = module._log;

local rawdebug = {};
def_env.rawdebug = rawdebug;

local function new_logger(log, prefix)
	local msg = prefix .. ": %s";
	return function (data)
		log("debug", msg, tostring(data))
		return data;
	end
end

function rawdebug:enable(sessionid)
	local session = full_sessions[sessionid];
	if not session then
		return nil, "No such session";
	end
	local f = {
		["stanzas/in"]  = new_logger(session.log or log, "RECV");
		["stanzas/out"] = new_logger(session.log or log, "SEND");
	};
	for type, callback in pairs(f) do
		filters.add_filter(session, type, callback)
	end
	rawdebug_enabled[session] = f;
end

function rawdebug:disable(sessionid)
	local session = full_sessions[sessionid];
	if not session then
		return nil, "No such session";
	end
	local f = rawdebug_enabled[session];
	for type, callback in pairs(f) do
		filters.remove_filter(session, type, callback)
	end
end

function module.unload()
	def_env.rawdebug = nil;
	for session, f in pairs(rawdebug_enabled) do
		for type, callback in pairs(f) do
			filters.remove_filter(session, type, callback)
		end
	end
end

