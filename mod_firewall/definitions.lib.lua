
local definition_handlers = {};

local new_throttle = require "util.throttle".create;

function definition_handlers.ZONE(zone_name, zone_members)
			local zone_member_list = {};
			for member in zone_members:gmatch("[^, ]+") do
				zone_member_list[#zone_member_list+1] = member;
			end
			return set.new(zone_member_list)._items;
end

function definition_handlers.RATE(name, line)
			local rate = assert(tonumber(line:match("([%d.]+)")), "Unable to parse rate");
			local burst = tonumber(line:match("%(%s*burst%s+([%d.]+)%s*%)")) or 1;
			return new_throttle(rate*burst, burst);
end

return definition_handlers;
