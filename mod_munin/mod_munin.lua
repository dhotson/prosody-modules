module:set_global();

local s_format = string.format;
local array = require"util.array";
local it = require"util.iterators";
local mt = require"util.multitable";

local meta = mt.new(); meta.data = module:shared"meta";
local data = mt.new(); data.data = module:shared"data";

local munin_listener = {};
local munin_commands = {};

local node_name = module:get_option_string("munin_node_name", "localhost");
local ignore_stats = module:get_option_set("munin_ignored_stats", { });

local function clean_fieldname(name)
	return (name:gsub("[^A-Za-z0-9_]", "_"):gsub("^[^A-Za-z_]", "_%1"));
end

function munin_listener.onconnect(conn)
	-- require"core.statsmanager".collect();
	conn:write("# munin node at "..node_name.."\n");
end

function munin_listener.onincoming(conn, line)
	line = line and line:match("^[^\r\n]+");
	if type(line) ~= "string" then return end
	-- module:log("debug", "incoming: %q", line);
	local command = line:match"^%w+";
	command = munin_commands[command];
	if not command then
		conn:write("# Unknown command.\n");
		return;
	end
	local ok, err = pcall(command, conn, line);
	if not ok then
		module:log("error", "Error running %q: %s", line, err);
		conn:close();
	end
end

function munin_listener.ondisconnect() end

function munin_commands.cap(conn)
	conn:write("cap\n");
end

function munin_commands.list(conn)
	conn:write(array(it.keys(data.data)):concat(" ") .. "\n");
end

function munin_commands.config(conn, line)
	-- TODO what exactly?
	local stat = line:match("%s(%S+)");
	if not stat then conn:write("# Unknown service\n.\n"); return end
	for _, _, k, value in meta:iter(stat, "", nil) do
		conn:write(s_format("%s %s\n", k, value));
	end
	for _, name, k, value in meta:iter(stat, nil, nil) do
		if name ~= "" and not ignore_stats:contains(name) then
			conn:write(s_format("%s.%s %s\n", name, k, value));
		end
	end
	conn:write(".\n");
end

function munin_commands.fetch(conn, line)
	local stat = line:match("%s(%S+)");
	if not stat then conn:write("# Unknown service\n.\n"); return end
	for _, name, value in data:iter(stat, nil) do
		if not ignore_stats:contains(name) then
			conn:write(s_format("%s.value %.12f\n", name, value));
		end
	end
	conn:write(".\n");
end

function munin_commands.quit(conn)
	conn:close();
end

module:hook("stats-updated", function (event)
	local all_stats, this = event.stats_extra;
	local host, sect, name, typ, key;
	for stat, value in pairs(event.changed_stats) do
		if not ignore_stats:contains(stat) then
			this = all_stats[stat];
			-- module:log("debug", "changed_stats[%q] = %s", stat, tostring(value));
			host, sect, name, typ = stat:match("^/([^/]+)/([^/]+)/(.+):(%a+)$");
			if host == nil then
				sect, name, typ, host = stat:match("^([^.]+)%.([^:]+):(%a+)$");
			elseif host == "*" then
				host = nil;
			end
			key = clean_fieldname(s_format("%s_%s_%s", host or "global", sect, typ));

			if not meta:get(key) then
				if host then
					meta:set(key, "", "graph_title", s_format("%s %s on %s", sect, typ, host));
				else
					meta:set(key, "", "graph_title", s_format("Global %s %s", sect, typ, host));
				end
				meta:set(key, "", "graph_vlabel", this and this.units or typ);
				meta:set(key, "", "graph_category", sect);

				meta:set(key, name, "label", name);
			elseif not meta:get(key, name, "label") then
				meta:set(key, name, "label", name);
			end

			data:set(key, name, value);
		end
	end
end);

module:provides("net", {
	listener = munin_listener;
	default_mode = "*l";
	default_port = 4949;
});

