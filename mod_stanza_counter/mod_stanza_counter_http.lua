-- (C) 2011, Marco Cirillo (LW.Org)
-- Exposes stats on HTTP for the stanza counter module.

module:set_global()

local ports = module:get_option_array("stanza_counter_http_ports", {{ port = 5280 }})

local httpserver = require "net.httpserver"

-- http handlers

local r_200 = "\n<html>\n<head>\n<title>Prosody's Stanza Counter</title>\n<meta name=\"robots\" content=\"noindex, nofollow\" />\n</head>\n\n<body>\n<h3>Incoming and Outgoing stanzas divided per type</h3>\n<p><strong>Incoming IQs</strong>: %d<br/>\n<strong>Outgoing IQs</strong>: %d<br/>\n<strong>Incoming Messages</strong>: %d<br/>\n<strong>Outgoing Messages</strong>: %d<br/>\n<strong>Incoming Presences</strong>: %d<br/>\n<strong>Outgoing Presences</strong>: %d<p>\n</body>\n\n</html>\n"

local r_err = "\n<html>\n<head>\n<title>Prosody's Stanza Counter - Error %s</title>\n<meta name=\"robots\" content=\"noindex, nofollow\" />\n</head>\n\n<body>\n<h3>%s</h3>\n</body>\n\n</html>\n"

local function res(code, r, h)
	local response = {
		status = code,
		body = r
	}
	
        if h then response.headers = h end
        return response
end

local function req(method, body, request)
	if not prosody.stanza_counter then
		local err500 = r_err:format("500", "Stats not found, is the counter module loaded?")
		return res(500, err500) end
	if method == "GET" then
		local forge_res = r_200:format(prosody.stanza_counter.iq["incoming"],
					       prosody.stanza_counter.iq["outgoing"],
					       prosody.stanza_counter.message["incoming"],
					       prosody.stanza_counter.message["outgoing"],
					       prosody.stanza_counter.presence["incoming"],
					       prosody.stanza_counter.presence["outgoing"])
		return res(200, forge_res)
	else
		local err405 = r_err:format("405", "Only GET is supported")
		return res(405, err405, {["Allow"] = "GET"})
	end
end

-- initialization.
-- init http and cleanup interface

function sc_cleanup() -- recycled from mod_register_json, it's handy
        module:log("debug", "Cleaning up handlers and stuff as module is being unloaded.")
        for _, options in ipairs(ports) do
                if options.port then
                        httpserver.new.http_servers[options.port].handlers[options.path or "stanza-counter"] = nil
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

        prosody.events.remove_handler("module-unloaded", sc_cleanup)
end

local function setup()
	httpserver.new_from_config(ports, req, { base = "stanza-counter" })
	prosody.events.add_handler("module-unloaded", sc_cleanup)
end

-- set it
if prosody.start_time then setup() else	module:hook("server-started", setup) end
