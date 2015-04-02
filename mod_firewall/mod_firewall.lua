
local resolve_relative_path = require "core.configmanager".resolve_relative_path;
local logger = require "util.logger".init;
local set = require "util.set";
local it = require "util.iterators";
local add_filter = require "util.filters".add_filter;

local definitions = module:shared("definitions");
local active_definitions = {};

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

local function idsafe(name)
	return not not name:match("^%a[%w_]*$")
end

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
	st = { global_code = [[local st = require "util.stanza";]]};
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
	zone = { global_code = function (zone)
		assert(idsafe(zone), "Invalid zone name: "..zone);
		return ("local zone_%s = zones[%q] or {};"):format(zone, zone);
	end };
	date_time = { global_code = [[local os_date = os.date]]; local_code = [[local current_date_time = os_date("*t");]] };
	time = { local_code = function (what)
		local defs = {};
		for field in what:gmatch("%a+") do
			table.insert(defs, ("local current_%s = current_date_time.%s;"):format(field, field));
		end
		return table.concat(defs, " ");
	end, depends = { "date_time" }; };
	throttle = {
		global_code = function (throttle)
			assert(idsafe(throttle), "Invalid rate limit name: "..throttle);
			assert(active_definitions.RATE[throttle], "Unknown rate limit: "..throttle);
			return ("local throttle_%s = rates.%s;"):format(throttle, throttle);
		end;
	};
};

local function include_dep(dep, code)
	local dep, dep_param = dep:match("^([^:]+):?(.*)$");
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
		if dep_param ~= "" then
			table.insert(code.global_header, dep_info.global_code(dep_param));
		else
			table.insert(code.global_header, dep_info.global_code);
		end
	end
	if dep_info.local_code then
		if dep_param ~= "" then
			table.insert(code, "\n\t\t-- "..dep.."\n\t\t"..dep_info.local_code(dep_param).."\n");
		else
			table.insert(code, "\n\t\t-- "..dep.."\n\t\t"..dep_info.local_code.."\n");
		end
	end
	code.included_deps[dep] = true;
end

local definition_handlers = module:require("definitions");
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
			local chain_info = chains[chain];
			if not chain_info then
				return nil, errmsg("Unknown chain: "..chain);
			elseif chain_info.type ~= "event" then
				return nil, errmsg("Only event chains supported at the moment");
			end
			ruleset[chain] = ruleset[chain] or {};
		elseif not(state) and line:match("^%%") then -- Definition (zone, limit, etc.)
			local what, name = line:match("^%%%s*(%w+) +([^ :]+)");
			if not definition_handlers[what] then
				return nil, errmsg("Definition of unknown object: "..what);
			elseif not name or not idsafe(name) then
				return nil, errmsg("Invalid "..what.." name");
			end

			local val = line:match(": ?(.*)$");
			if not val and line:match(":<") then -- Read from file
				local fn = line:match(":< ?(.-)%s*$");
				if not fn then
					return nil, errmsg("Unable to parse filename");
				end
				local f, err = io.open(fn);
				if not f then return nil, errmsg(err); end
				val = f:read("*a"):gsub("\r?\n", " "):gsub("%s+5", "");
			end
			if not val then
				return nil, errmsg("No value given for definition");
			end

			local ok, ret = pcall(definition_handlers[what], name, val);
			if not ok then
				return nil, errmsg(ret);
			end

			if not active_definitions[what] then
				active_definitions[what] = {};
			end
			active_definitions[what][name] = ret;
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
			condition = condition:gsub(" ", "_");
			if not condition_handlers[condition] then
				return nil, ("Unknown condition on line %d: %s"):format(line_no, (condition:gsub("_", " ")));
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
		local condition_uses = {};
		-- This inner loop assumes chain is an event-based, not a filter-based
		-- chain (filter-based will be added later)
		for _, rule in ipairs(rules) do
			for _, condition in ipairs(rule.conditions) do
				if condition:match("^not%(.+%)$") then
					condition = condition:match("^not%((.+)%)$");
				end
				condition_uses[condition] = (condition_uses[condition] or 0) + 1;
			end
		end

		local condition_cache, n_conditions = {}, 0;
		for _, rule in ipairs(rules) do
			for _, dep in ipairs(rule.deps) do
				include_dep(dep, code);
			end
			table.insert(code, "\n\t\t");
			local rule_code;
			if #rule.conditions > 0 then
				for i, condition in ipairs(rule.conditions) do
					local negated = condition:match("^not%(.+%)$");
					if negated then
						condition = condition:match("^not%((.+)%)$");
					end
					if condition_uses[condition] > 1 then
						local name = condition_cache[condition];
						if not name then
							n_conditions = n_conditions + 1;
							name = "condition"..n_conditions;
							condition_cache[condition] = name;
							table.insert(code, "local "..name.." = "..condition..";\n\t\t");
						end
						rule.conditions[i] = (negated and "not(" or "")..name..(negated and ")" or "");
					else
						rule.conditions[i] = (negated and "not(" or "(")..condition..")";
					end
				end

				rule_code = "if "..table.concat(rule.conditions, " and ").." then\n\t\t\t"
					..table.concat(rule.actions, "\n\t\t\t")
					.."\n\t\tend\n";
			else
				rule_code = table.concat(rule.actions, "\n\t\t");
			end
			table.insert(code, rule_code);
		end

		for name in pairs(definition_handlers) do
			table.insert(code.global_header, 1, "local "..name:lower().."s = definitions."..name..";");
		end

		local code_string = "return function (definitions, fire_event, log)\n\t"
			..table.concat(code.global_header, "\n\t")
			.."\n\tlocal db = require 'util.debug';\n\n\t"
			.."return function (event)\n\t\t"
			.."local stanza, session = event.stanza, event.origin;\n"
			..table.concat(code, "")
			.."\n\tend;\nend";

		chain_handlers[chain_name] = code_string;
	end

	return chain_handlers;
end

local function compile_handler(code_string, filename)
	-- Prepare event handler function
	local chunk, err = loadstring(code_string, "="..filename);
	if not chunk then
		return nil, "Error compiling (probably a compiler bug, please report): "..err;
	end
	local function fire_event(name, data)
		return module:fire_event(name, data);
	end
	chunk = chunk()(active_definitions, fire_event, logger(filename)); -- Returns event handler with 'zones' upvalue.
	return chunk;
end

function module.load()
	if not prosody.arg then return end -- Don't run in prosodyctl
	active_definitions = {};
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
					elseif not chain:match("^user/") then
						module:log("warn", "Unknown chain %q", chain);
					end
					module:hook("firewall/chains/"..chain, handler);
				end
			end
		end
	end
	-- Replace contents of definitions table (shared) with active definitions
	for k in it.keys(definitions) do definitions[k] = nil; end
	for k,v in pairs(active_definitions) do definitions[k] = v; end
end

function module.command(arg)
	if not arg[1] or arg[1] == "--help" then
		require"util.prosodyctl".show_usage([[mod_firewall <firewall.pfw>]], [[Compile files with firewall rules to Lua code]]);
		return 1;
	end

	for _, filename in ipairs(arg) do
		print("\n-- File "..filename);
		local chain_functions = assert(compile_firewall_rules(arg[1]));
		for chain, handler_code in pairs(chain_functions) do
			print("\n---- Chain "..chain);
			print(handler_code);
			print("\n---- End of chain "..chain);
		end
		print("\n-- End of file "..filename);
	end
end
