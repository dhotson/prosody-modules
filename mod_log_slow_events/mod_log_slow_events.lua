local time = require "socket".gettime;

local max_seconds = module:get_option_number("log_slow_events_threshold", 0.5);

module:wrap_event(false, function (handlers, event_name, event_data)
	local start = time();
	local ret = handlers(event_name, event_data);
	local duration = time()-start;
	if duration > max_seconds then
		local data = {};
		if event_data then
			local function log_data(name, value)
				if value then
					table.insert(data, ("%s=%q"):format(name, value));
					return true;
				end
			end
			local sess = event_data.origin or event_data.session;
			if sess then
				log_data("ip", sess.ip);
				if not log_data("full_jid", sess.full_jid) then
					log_data("username", sess.username);
				end
				log_data("type", sess.type);
				log_data("host", sess.host);
			end
			local stanza = event_data.stanza;
			if stanza then
				log_data("stanza", tostring(stanza));
			end
		end
		module:log("warn", "Slow event '%s' took %0.2f: %s", event_name, duration, next(data) and table.concat(data, ", ") or "no recognised data");
	end
	return ret;
end);
