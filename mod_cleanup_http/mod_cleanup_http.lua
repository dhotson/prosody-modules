-- Auto-cleanup for Global BOSH modules.
-- Should take care of spring cleaning without messing in either the console, or restarting

module:set_global()

local http_modules = module:get_option("cleanup_http_modules", {})
if type(http_modules) ~= "table" then module:log("error", "cleanup_http_modules needs to be a module.") ; return false end

local function cleanup(data)
	if data.module == "cleanup_http" then -- it's us getting unloaded destroy handler.
		prosody.events.remove_handler("module-unloaded", cleanup)
	elseif http_modules[data.module] then
		local ports = http_modules[data.module]

		module:log("debug", "Cleaning up http handlers and ports as module %s is being unloaded.", data.module)
		for _, options in ipairs(ports) do
			if options.port then
                        	httpserver.new.http_servers[options.port].handlers[options.path or "register_account"] = nil
			end
		end

		-- if there are no handlers left clean and close the socket, doesn't work with server_event
		local event = require "core.configmanager".get("*", "core", "use_libevent")

		if not event then
        	        for _, options in ipairs(ports) do
                	        if options.port and not next(httpserver.new.http_servers[options.port].handlers) then
                        	        httpserver.new.http_servers[options.port] = nil
					if options.interface then
						for _, value in ipairs(options.interface) do
							if server.getserver(value, options.port) then server.removeserver(value, options.port) end
						end
					else if server.getserver("*", options.port) then server.removeserver("*", options.port) end end
				end
			end
		end
	end
end

prosody.events.add_handler("module-unloaded", cleanup)
