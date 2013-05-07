local condition_handlers = {};

local jid = require "util.jid";

-- Return a code string for a condition that checks whether the contents
-- of variable with the name 'name' matches any of the values in the
-- comma/space/pipe delimited list 'values'.
local function compile_comparison_list(name, values)
	local conditions = {};
	for value in values:gmatch("[^%s,|]+") do
		table.insert(conditions, ("%s == %q"):format(name, value));
	end
	return table.concat(conditions, " or ");
end

function condition_handlers.KIND(kind)
	return compile_comparison_list("name", kind), { "name" };
end

local wildcard_equivs = { ["*"] = ".*", ["?"] = "." };

local function compile_jid_match_part(part, match)
	if not match then
		return part.." == nil"
	end
	local pattern = match:match("<(.*)>");
	if pattern then
		if pattern == "*" then
			return part;
		end
		if pattern:match("^<.*>$") then
			pattern = pattern:match("^<(.*)>$");
		else
			pattern = pattern:gsub("%p", "%%%0"):gsub("%%(%p)", wildcard_equivs);
		end
		return ("%s:match(%q)"):format(part, "^"..pattern.."$");
	else
		return ("%s == %q"):format(part, match);
	end
end

local function compile_jid_match(which, match_jid)
	local match_node, match_host, match_resource = jid.split(match_jid);
	local conditions = {};
	conditions[#conditions+1] = compile_jid_match_part(which.."_node", match_node);
	conditions[#conditions+1] = compile_jid_match_part(which.."_host", match_host);
	if match_resource then
		conditions[#conditions+1] = compile_jid_match_part(which.."_resource", match_resource);
	end
	return table.concat(conditions, " and ");
end

function condition_handlers.TO(to)
	return compile_jid_match("to", to), { "split_to" };
end

function condition_handlers.FROM(from)
	return compile_jid_match("from", from), { "split_from" };
end

function condition_handlers.TYPE(type)
	return compile_comparison_list("(type or (name == 'message' and 'normal') or (name == 'presence' and 'available'))", type), { "type", "name" };
end

local function zone_check(zone, which)
	local which_not = which == "from" and "to" or "from";
	return ("(zone_%s[%s_host] or zone_%s[%s] or zone_%s[bare_%s]) "
		.."and not(zone_%s[%s_host] or zone_%s[%s] or zone_%s[%s])"
		)
		:format(zone, which, zone, which, zone, which,
		zone, which_not, zone, which_not, zone, which_not), {
			"split_to", "split_from", "bare_to", "bare_from", "zone:"..zone
		};
end

function condition_handlers.ENTERING(zone)
	return zone_check(zone, "to");
end

function condition_handlers.LEAVING(zone)
	return zone_check(zone, "from");
end

function condition_handlers.PAYLOAD(payload_ns)
	return ("stanza:get_child(nil, %q)"):format(payload_ns);
end

function condition_handlers.INSPECT(path)
	if path:find("=") then
		local path, match = path:match("(.-)=(.*)");
		return ("stanza:find(%q) == %q"):format(path, match);
	end
	return ("stanza:find(%q)"):format(path);
end

function condition_handlers.FROM_GROUP(group_name)
	return ("group_contains(%q, bare_from)"):format(group_name), { "group_contains", "bare_from" };
end

function condition_handlers.TO_GROUP(group_name)
	return ("group_contains(%q, bare_to)"):format(group_name), { "group_contains", "bare_to" };
end

function condition_handlers.FROM_ADMIN_OF(host)
	return ("is_admin(bare_from, %s)"):format(host ~= "*" and host or nil), { "is_admin", "bare_from" };
end

function condition_handlers.TO_ADMIN_OF(host)
	return ("is_admin(bare_to, %s)"):format(host ~= "*" and host or nil), { "is_admin", "bare_to" };
end

local day_numbers = { sun = 0, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 };

local function current_time_check(op, hour, minute)
	hour, minute = tonumber(hour), tonumber(minute);
	local adj_op = op == "<" and "<" or ">="; -- Start time inclusive, end time exclusive
	if minute == 0 then
		return "(current_hour"..adj_op..hour..")";
	else
		return "((current_hour"..op..hour..") or (current_hour == "..hour.." and current_minute"..adj_op..minute.."))";
	end
end

local function resolve_day_number(day_name)
	return assert(day_numbers[day_name:sub(1,3):lower()], "Unknown day name: "..day_name);
end

function condition_handlers.DAY(days)
	local conditions = {};
	for day_range in days:gmatch("[^,]+") do
		local day_start, day_end = day_range:match("(%a+)%s*%-%s*(%a+)");
		if day_start and day_end then
			local day_start_num, day_end_num = resolve_day_number(day_start), resolve_day_number(day_end);
			local op = "and";
			if day_end_num < day_start_num then
				op = "or";
			end
			table.insert(conditions, ("current_day >= %d %s current_day <= %d"):format(day_start_num, op, day_end_num));
		elseif day_range:match("%a") then
			local day = resolve_day_number(day_range:match("%a+"));
			table.insert(conditions, "current_day == "..day);
		else
			error("Unable to parse day/day range: "..day_range);
		end
	end
	assert(#conditions>0, "Expected a list of days or day ranges");
	return "("..table.concat(conditions, ") or (")..")", { "time:day" };
end

function condition_handlers.TIME(ranges)
	local conditions = {};
	for range in ranges:gmatch("([^,]+)") do
		local clause = {};
		range = range:lower()
			:gsub("(%d+):?(%d*) *am", function (h, m) return tostring(tonumber(h)%12)..":"..(tonumber(m) or "00"); end)
			:gsub("(%d+):?(%d*) *pm", function (h, m) return tostring(tonumber(h)%12+12)..":"..(tonumber(m) or "00"); end);
		local start_hour, start_minute = range:match("(%d+):(%d+) *%-");
		local end_hour, end_minute = range:match("%- *(%d+):(%d+)");
		local op = tonumber(start_hour) > tonumber(end_hour) and " or " or " and ";
		if start_hour and end_hour then
			table.insert(clause, current_time_check(">", start_hour, start_minute));
			table.insert(clause, current_time_check("<", end_hour, end_minute));
		end
		if #clause == 0 then
			error("Unable to parse time range: "..range);
		end
		table.insert(conditions, "("..table.concat(clause, " "..op.." ")..")");
	end
	return table.concat(conditions, " or "), { "time:hour,min" };
end

function condition_handlers.LIMIT(name)
	return ("not throttle_%s:poll(1)"):format(name), { "throttle:"..name };
end

return condition_handlers;
