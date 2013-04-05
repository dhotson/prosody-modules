
local resolve_relative_path = require "core.configmanager".resolve_relative_path;
local logger = require "util.logger".init;
local set = require "util.set";
local add_filter = require "util.filters".add_filter;

zones = {};
local zones = zones;
setmetatable(zones, {
	__index = function (zones, zone)
		local t = { [zone] = true };
		rawset(zones, zone, t);
		return t;
	end;
});

local chains = {
	preroute = {
		type = "event";
		priority = 0.1;
		"pre-message/bare", "pre-message/full", "pre-message/host";
		"pre-presence/bare", "pre-presence/full", "pre-presence/host";
		"pre-iq/bare", "pre-iq/full", "pre-iq/host";
	};
	deliver = {
		type = "event";
		priority = 0.1;
		"message/bare", "message/full", "message/host";
		"presence/bare", "presence/full", "presence/host";
		"iq/bare", "iq/full", "iq/host";
	};
	deliver_remote = {
		type = "event"; "route/remote";
		priority = 0.1;
	};
};

-- Dependency locations:
-- <type lib>
-- <type global>
-- function handler()
--   <local deps>
--   if <conditions> then
--     <actions>
--   end
-- end

local available_deps = {
	st = { global_code = [[local st = require "util.stanza"]]};
	jid_split = {
		global_code = [[local jid_split = require "util.jid".split;]];
	};
	jid_bare = {
		global_code = [[local jid_bare = require "util.jid".bare;]];
	};
	to = { local_code = [[local to = stanza.attr.to;]] };
	from = { local_code = [[local from = stanza.attr.from;]] };
	type = { local_code = [[local type = stanza.attr.type;]] };
	name = { local_code = [[local name = stanza.name]] };
	split_to = { -- The stanza's split to address
		depends = { "jid_split", "to" };
		local_code = [[local to_node, to_host, to_resource = jid_split(to);]];
	};
	split_from = { -- The stanza's split from address
		depends = { "jid_split", "from" };
		local_code = [[local from_node, from_host, from_resource = jid_split(from);]];
	};
	bare_to = { depends = { "jid_bare", "to" }, local_code = "local bare_to = jid_bare(to)"};
	bare_from = { depends = { "jid_bare", "from" }, local_code = "local bare_from = jid_bare(from)"};
	group_contains = {
		global_code = [[local group_contains = module:depends("groups").group_contains]];
	};
	is_admin = { global_code = [[local is_admin = require "core.usermanager".is_admin]]};
	core_post_stanza = { global_code = [[local core_post_stanza = prosody.core_post_stanza]] };
};

local function include_dep(dep, code)
	local dep_info = available_deps[dep];
	if not dep_info then
		module:log("error", "Dependency not found: %s", dep);
		return;
	end
	if code.included_deps[dep] then
		if code.included_deps[dep] ~= true then
			module:log("error", "Circular dependency on %s", dep);
		end
		return;
	end
	code.included_deps[dep] = false; -- Pending flag (used to detect circular references)
	for _, dep_dep in ipairs(dep_info.depends or {}) do
		include_dep(dep_dep, code);
	end
	if dep_info.global_code then
		table.insert(code.global_header, dep_info.global_code);
	end
	if dep_info.local_code then
		table.insert(code, "\n\t-- "..dep.."\n\t"..dep_info.local_code.."\n\n\t");
	end
	code.included_deps[dep] = true;
end

local condition_handlers = module:require("conditions");
local action_handlers = module:require("actions");

local function new_rule(ruleset, chain)
	assert(chain, "no chain specified");
	local rule = { conditions = {}, actions = {}, deps = {} };
	table.insert(ruleset[chain], rule);
	return rule;
end

local function compile_firewall_rules(filename)
	local line_no = 0;
	
	local function errmsg(err)
		return "Error compiling "..filename.." on line "..line_no..": "..err;
	end
	
	local ruleset = {
		deliver = {};
	};

	local chain = "deliver"; -- Default chain
	local rule;
	
	local file, err = io.open(filename);
	if not file then return nil, err; end
	
	local state; -- nil -> "rules" -> "actions" -> nil -> ...
	
	local line_hold;
	for line in file:lines() do
		line = line:match("^%s*(.-)%s*$");
		if line_hold and line:sub(-1,-1) ~= "\\" then
			line = line_hold..line;
			line_hold = nil;
		elseif line:sub(-1,-1) == "\\" then
			line_hold = (line_hold or "")..line:sub(1,-2);
		end
		line_no = line_no + 1;
		
		if line_hold or line:match("^[#;]") then
			-- No action; comment or partial line
		elseif line == "" then
			if state == "rules" then
				return nil, ("Expected an action on line %d for preceding criteria")
					:format(line_no);
			end
			state = nil;
		elseif not(state) and line:match("^::") then
			chain = line:gsub("^::%s*", "");
			local chain_info = chains[chain_name];
			if not chain_info then
				return nil, errmsg("Unknown chain: "..chain_name);
			elseif chain_info.type ~= "event" then
				return nil, errmsg("Only event chains supported at the moment");
			end
			ruleset[chain] = ruleset[chain] or {};
		elseif not(state) and line:match("^ZONE ") then
			local zone_name = line:match("^ZONE ([^:]+)");
			if not zone_name:match("^%a[%w_]*$") then
				return nil, errmsg("Invalid character(s) in zone name: "..zone_name);
			end
			local zone_members = line:match("^ZONE .-: ?(.*)");
			local zone_member_list = {};
			for member in zone_members:gmatch("[^, ]+") do
				zone_member_list[#zone_member_list+1] = member;
			end
			zones[zone_name] = set.new(zone_member_list)._items;
		elseif line:match("^[^%s:]+[%.=]") then
			-- Action
			if state == nil then
				-- This is a standalone action with no conditions
				rule = new_rule(ruleset, chain);
			end
			state = "actions";
			-- Action handlers?
			local action = line:match("^%P+");
			if not action_handlers[action] then
				return nil, ("Unknown action on line %d: %s"):format(line_no, action or "<unknown>");
			end
			table.insert(rule.actions, "-- "..line)
			local ok, action_string, action_deps = pcall(action_handlers[action], line:match("=(.+)$"));
			if not ok then
				return nil, errmsg(action_string);
			end
			table.insert(rule.actions, action_string);
			for _, dep in ipairs(action_deps or {}) do
				table.insert(rule.deps, dep);
			end
		elseif state == "actions" then -- state is actions but action pattern did not match
			state = nil; -- Awaiting next rule, etc.
			table.insert(ruleset[chain], rule);
			rule = nil;
		else
			if not state then
				state = "rules";
				rule = new_rule(ruleset, chain);
			end
			-- Check standard modifiers for the condition (e.g. NOT)
			local negated;
			local condition = line:match("^[^:=%.]*");
			if condition:match("%f[%w]NOT%f[^%w]") then
				local s, e = condition:match("%f[%w]()NOT()%f[^%w]");
				condition = (condition:sub(1,s-1)..condition:sub(e+1, -1)):match("^%s*(.-)%s*$");
				negated = true;
			end
			condition = condition:gsub(" ", "");
			if not condition_handlers[condition] then
				return nil, ("Unknown condition on line %d: %s"):format(line_no, condition);
			end
			-- Get the code for this condition
			local ok, condition_code, condition_deps = pcall(condition_handlers[condition], line:match(":%s?(.+)$"));
			if not ok then
				return nil, errmsg(condition_code);
			end
			if negated then condition_code = "not("..condition_code..")"; end
			table.insert(rule.conditions, condition_code);
			for _, dep in ipairs(condition_deps or {}) do
				table.insert(rule.deps, dep);
			end
		end
	end
	
	-- Compile ruleset and return complete code
	
	local chain_handlers = {};

	-- Loop through the chains in the parsed ruleset (e.g. incoming, outgoing)
	for chain_name, rules in pairs(ruleset) do
		local code = { included_deps = {}, global_header = {} };
		-- This inner loop assumes chain is an event-based, not a filter-based
		-- chain (filter-based will be added later)
		for _, rule in ipairs(rules) do
			for _, dep in ipairs(rule.deps) do
				include_dep(dep, code);
			end
			local rule_code = "if ("..table.concat(rule.conditions, ") and (")..") then\n\t"
			..table.concat(rule.actions, "\n\t")
			.."\n end\n";
			table.insert(code, rule_code);
		end

		assert(chains[chain_name].type == "event", "Only event chains supported at the moment")

		local code_string = [[return function (zones, log)
			]]..table.concat(code.global_header, "\n")..[[
			local db = require 'util.debug'
			return function (event)
				local stanza, session = event.stanza, event.origin;

				]]..table.concat(code, " ")..[[
			end;
		end]];

		chain_handlers[chain_name] = code_string;
	end
		
	return chain_handlers;
end

local function compile_handler(code_string, filename)
	print(code_string)
	-- Prepare event handler function
	local chunk, err = loadstring(code_string, "="..filename);
	if not chunk then
		return nil, "Error compiling (probably a compiler bug, please report): "..err;
	end
	local function fire_event(name, data)
		return module:fire_event(name, data);
	end
	chunk = chunk()(zones, fire_event, logger(filename)); -- Returns event handler with 'zones' upvalue.
	return chunk;
end

function module.load()
	local firewall_scripts = module:get_option_set("firewall_scripts", {});
	for script in firewall_scripts do
		script = resolve_relative_path(prosody.paths.config, script);
		local chain_functions, err = compile_firewall_rules(script)
		
		if not chain_functions then
			module:log("error", "Error compiling %s: %s", script, err or "unknown error");
		else
			for chain, handler_code in pairs(chain_functions) do
				local handler, err = compile_handler(handler_code, "mod_firewall::"..chain);
				if not handler then
					module:log("error", "Compilation error for %s: %s", script, err);
				else
					local chain_definition = chains[chain];
					if chain_definition and chain_definition.type == "event" then
						for _, event_name in ipairs(chain_definition) do
							module:hook(event_name, handler, chain_definition.priority);
						end
					elseif not chain_name:match("^user/") then
						module:log("warn", "Unknown chain %q", chain);
					end
					module:hook("firewall/chains/"..chain, handler);
				end
			end
		end
	end
end
