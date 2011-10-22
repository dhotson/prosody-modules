-- Block or restrict by blacklist remote access to local components.

local guard_blockall = module:get_option_set("component_guard_blockall")
local guard_protect = module:get_option_set("component_guard_components")
local guard_block_bl = module:get_option_set("component_guard_blacklist")

local s2smanager = require "core.s2smanager";
local config = require "core.configmanager";
local nameprep = require "util.encodings".stringprep.nameprep;

local _make_connect = s2smanager.make_connect;
function s2smanager.make_connect(session, connect_host, connect_port)
  if not session.s2sValidation then
    if guard_blockall:contains(session.from_host) or
       guard_block_bl:contains(session.to_host) and guard_protect:contains(session.from_host) then
         module:log("error", "remote service %s attempted to access restricted component %s", session.to_host, session.from_host);
         s2smanager.destroy_session(session, "You're not authorized, good bye.");
         return false;
    end
  end
  return _make_connect(session, connect_host, connect_port);
end

local _stream_opened = s2smanager.streamopened;
function s2smanager.streamopened(session, attr)
  local host = attr.to and nameprep(attr.to);
  local from = attr.from and nameprep(attr.from);
    if not from then
      session.s2sValidation = false;
    else
      session.s2sValidation = true;
    end

    if guard_blockall:contains(host) or
       guard_block_bl:contains(from) and guard_protect:contains(host) then
         module:log("error", "remote service %s attempted to access restricted component %s", from, host);
         session:close({condition = "policy-violation", text = "You're not authorized, good bye."});
         return false;
    end
    _stream_opened(session, attr);
end

local function sdr_hook (event)
	local origin, stanza = event.origin, event.stanza;

	if origin.type == "s2sin" or origin.type == "s2sin_unauthed" then
	   if guard_blockall:contains(stanza.attr.to) or 
	      guard_block_bl:contains(stanza.attr.from) and guard_protect:contains(stanza.attr.to) then
                module:log("error", "remote service %s attempted to access restricted component %s", stanza.attr.from, stanza.attr.to);
                origin:close({condition = "policy-violation", text = "You're not authorized, good bye."});
                return false;
           end
        end

	return nil;
end

local function handle_activation (host)
	if guard_blockall:contains(host) or guard_protect:contains(host) then
		if hosts[host] and hosts[host].events then
			hosts[host].events.add_handler("stanza/jabber:server:dialback:result", sdr_hook, 100);
                	module:log ("debug", "adding component protection for: "..host);
		end
	end
end

local function handle_deactivation (host)
	if guard_blockall:contains(host) or guard_protect:contains(host) then
		if hosts[host] and hosts[host].events then
			hosts[host].events.remove_handler("stanza/jabber:server:dialback:result", sdr_hook);
                	module:log ("debug", "removing component protection for: "..host);
		end
	end
end

local function reload()
	module:log ("debug", "server configuration reloaded, rehashing plugin tables...");
	guard_blockall = module:get_option_set("component_guard_blockall");
	guard_protect = module:get_option_set("component_guard_components");
	guard_block_bl = module:get_option_set("component_guard_blacklist");
end

local function setup()
	module:log ("debug", "initializing component guard module...");

	prosody.events.remove_handler("component-activated", handle_activation);
	prosody.events.add_handler("component-activated", handle_activation);
	prosody.events.remove_handler("component-deactivated", handle_deactivation);
	prosody.events.add_handler("component-deactivated", handle_deactivation);
	prosody.events.remove_handler("config-reloaded", reload);
	prosody.events.add_handler("config-reloaded", reload);

	for n,table in pairs(hosts) do
		if table.type == "component" then
			if guard_blockall:contains(n) or guard_protect:contains(n) then
				hosts[n].events.remove_handler("stanza/jabber:server:dialback:result", sdr_hook);
				handle_activation(n);
			end
		end
	end
end

if prosody.start_time then
	setup();
else
	prosody.events.add_handler("server-started", setup);
end
