-- Copyright (C) 2012-2013 Kim Alvefur

local um = require "core.usermanager";
local sm = require "core.storagemanager";
local dm_load = require "util.datamanager".load;
local jid_join = require"util.jid".join;

local multipliers = {
	d = 86400, -- day
	w = 604800, -- week
	m = 2629746, -- month
	y = 31556952, -- year
}

function module.command(arg)
	local items = {};
	local host = arg[1];
	assert(hosts[host], "Host "..tostring(host).." does not exist");
	sm.initialize_host(host);
	um.initialize_host(host);

	local max_age, unit = assert(arg[2], "No time range given"):match("^(%d*)%s*([dwmy]?)");
	max_age = os.time() - ( tonumber(max_age) or 1 ) * ( multipliers[unit] or 1 );
	for user in um.users(host) do
		local last_active = dm_load(user, host, "lastlog");
		last_active = last_active and last_active.timestamp or 0;
		if last_active < max_age then
			print(("user:delete%q"):format(jid_join(user, host)));
		end
	end
end

