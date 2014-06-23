-- HTTP Strict Transport Security
-- https://tools.ietf.org/html/rfc6797

module:set_global();

local http_server = require "net.http.server";

local hsts_header = module:get_option_string("hsts_header", "max-age=31556952"); -- This means "Don't even try to access without HTTPS for a year"

local _old_send_response;
local _old_fire_event;

local modules = {};

function module.load()
	_old_send_response = http_server.send_response;
	function http_server.send_response(response, body)
		response.headers.strict_transport_security = hsts_header;
		return _old_send_response(response, body);
	end

	_old_fire_event = http_server._events.fire_event;
	function http_server._events.fire_event(event, payload)
		local request = payload.request;
		local host = event:match("^[A-Z]+ ([^/]+)");
		local module = modules[host];
		if module and not request.secure then
			payload.response.headers.location = module:http_url(request.path);
			return 301;
		end
		return _old_fire_event(event, payload);
	end
end
function module.unload()
	http_server.send_response = _old_send_response;
	http_server._events.fire_event = _old_fire_event;
end
function module.add_host(module)
	local http_host = module:get_option_string("http_host", module.host);
	modules[http_host] = module;
	function module.unload()
		modules[http_host] = nil;
	end
end
