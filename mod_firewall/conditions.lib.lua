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
	-- TODO: Support Lua pattern matching (main issue syntax... << >>?)
	if pattern then
		if pattern ~= "*" then
			return ("%s:match(%q)"):format(part, pattern:gsub(".", wildcard_equivs));
		end
	else
		return ("%s == %q"):format(part, match);
	end
end

local function compile_jid_match(which, match_jid)
	local match_node, match_host, match_resource = jid.split(match_jid);
	local conditions = {
		compile_jid_match_part(which.."_node", match_node);
		compile_jid_match_part(which.."_host", match_host);
		match_resource and compile_jid_match_part(which.."_resource", match_resource) or nil;
	};
	return table.concat(conditions, " and ");
end

function condition_handlers.TO(to)
	return compile_jid_match("to", to), { "split_to" };
end

function condition_handlers.FROM(from)
	return compile_jid_match("from", from), { "split_from" };
end

function condition_handlers.TYPE(type)
	return compile_comparison_list("type", type), { "type" };
end

function condition_handlers.ENTERING(zone)
	return ("(zones[%q] and (zones[%q][to_host] or "
		.."zones[%q][to] or "
		.."zones[%q][bare_to]))"
		)
		:format(zone, zone, zone, zone), { "split_to", "bare_to" };
end

function condition_handlers.LEAVING(zone)
	return ("zones[%q] and (zones[%q][from_host] or "
		.."(zones[%q][from] or "
		.."zones[%q][bare_from]))")
		:format(zone, zone, zone, zone), { "split_from", "bare_from" };
end

function condition_handlers.PAYLOAD(payload_ns)
	return ("stanza:get_child(nil, %q)"):format(payload_ns);
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

return condition_handlers;
