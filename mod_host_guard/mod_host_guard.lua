-- (C) 2011, Marco Cirillo (LW.Org)
-- Block or restrict by blacklist remote access to local components or hosts.

module:set_global()

local guard_blockall = module:get_option_set("host_guard_blockall", {})
local guard_ball_wl = module:get_option_set("host_guard_blockall_exceptions", {})
local guard_protect = module:get_option_set("host_guard_selective", {})
local guard_block_bl = module:get_option_set("host_guard_blacklist", {})

local config = require "core.configmanager"
local nameprep = require "util.encodings".stringprep.nameprep

local function s2s_hook (event)
	local origin, stanza = event.session or event.origin, event.stanza or false
	local to_host, from_host = (not stanza and origin.to_host) or stanza.attr.to, (not stanza and origin.from_host) or stanza.attr.from

	if origin.type == "s2sin" or origin.type == "s2sin_unauthed" then
	   if guard_blockall:contains(to_host) and not guard_ball_wl:contains(from_host) or
	      guard_block_bl:contains(from_host) and guard_protect:contains(to_host) then
                module:log("error", "remote service %s attempted to access restricted host %s", stanza.attr.from, stanza.attr.to)
                origin:close({condition = "policy-violation", text = "You're not authorized, good bye."})
                return false
           end
        end

	return nil
end

local function handle_activation (host)
	if guard_blockall:contains(host) or guard_protect:contains(host) then
		if hosts[host] and hosts[host].events then
			hosts[host].events.add_handler("s2sin-established", s2s_hook, 500)
			hosts[host].events.add_handler("stanza/jabber:server:dialback:result", s2s_hook, 500)
                	module:log ("debug", "adding host protection for: "..host)
		end
	end
end

local function handle_deactivation (host)
	if guard_blockall:contains(host) or guard_protect:contains(host) then
		if hosts[host] and hosts[host].events then
			hosts[host].events.remove_handler("s2sin-established", s2s_hook)
			hosts[host].events.remove_handler("stanza/jabber:server:dialback:result", s2s_hook)
                	module:log ("debug", "removing host protection for: "..host)
		end
	end
end

local function init_hosts()
	for n,table in pairs(hosts) do
		hosts[n].events.remove_handler("s2sin-established", s2s_hook)
		hosts[n].events.remove_handler("stanza/jabber:server:dialback:result", s2s_hook)
		if guard_blockall:contains(n) or guard_protect:contains(n) then	handle_activation(n) end
	end
end

local function reload()
	module:log ("debug", "server configuration reloaded, rehashing plugin tables...")
	guard_blockall = module:get_option_set("host_guard_blockall", {})
	guard_ball_wl = module:get_option_set("host_guard_blockall_exceptions", {})
	guard_protect = module:get_option_set("host_guard_selective", {})
	guard_block_bl = module:get_option_set("host_guard_blacklist", {})

	init_hosts()
end

local function setup()
        module:log ("debug", "initializing host guard module...")
        module:hook ("host-activated", handle_activation)
        module:hook ("host-deactivated", handle_deactivation)
        module:hook ("config-reloaded", reload)

        init_hosts()
end

if prosody.start_time then
	setup()
else
	module:hook ("server-started", setup)
end
