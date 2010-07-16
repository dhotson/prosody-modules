local modulemanager = require "core.modulemanager";
local config = require "core.configmanager";

module.host = "*";

local function reload_components()
        module:log ("debug", "reload_components");

        local defined_hosts = config.getconfig();

        for host in pairs(defined_hosts) do
                module:log ("debug", "found host %s", host);
                if (not hosts[host] and host ~= "*") then
                        module:log ("debug", "found new host %s", host);
                        modulemanager.load(host, configmanager.get(host, "core", "component_module"));
                end
        end;

        return;
end

module:hook("config-reloaded", reload_components);

