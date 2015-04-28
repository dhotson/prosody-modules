module:set_global();

local helpers = require "util.helpers";

helpers.log_events(prosody.events, "global", module._log);

function module.add_host(module)
	helpers.log_events(prosody.hosts[module.host].events, module.host, module._log);
end

function module.remove_host(module)
	helpers.revert_log_events(prosody.hosts[module.host].events);
end
