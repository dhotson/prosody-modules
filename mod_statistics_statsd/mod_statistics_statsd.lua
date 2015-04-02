local statsmanager = require "core.statsmanager";
local udp = require "socket".udp();

local server = module:get_option_string("statsd_server_ip", "127.0.0.1");
local server_port = module:get_option_number("statsd_server_port", 8124);
local max_datagram_size = module:get_option_number("statds_packet_size", 512);

function push_stats(stats, meta)
	local metric_strings, remaining_bytes = {}, max_datagram_size;
	for name, value in pairs(stats) do
		local value_meta = meta[name];
		log("warn", "%s %s", name, tostring(value_meta));
		--if not value_meta then
			-- Simple value (gauge)
			local metric_string = ("%s|%d|g"):format(name, value);
			if #metric_string > remaining_bytes then
				udp:sendto(table.concat(metric_strings, "\n"), server, server_port);
				metric_strings, remaining_bytes = {}, max_datagram_size;
			end
			table.insert(metric_strings, metric_string);
			remaining_bytes = remaining_bytes - (#metric_string + 1); -- +1 for newline
		--end
	end
	if #metric_strings > 0 then
		udp:sendto(table.concat(metric_strings, "\n"), server, server_port);
	end
end

module:hook_global("stats-updated", function (event)
	push_stats(event.changed_stats, event.stats_extra);
end);

function module.load()
	local all, changed, extra = statsmanager.get_stats();
	push_stats(all, extra);
end
