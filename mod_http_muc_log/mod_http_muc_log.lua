local st = require "util.stanza";
local datetime = require"util.datetime";
local jid_split = require"util.jid".split;
local nodeprep = require"util.encodings".stringprep.nodeprep;
local uuid = require"util.uuid".generate;
local it = require"util.iterators";
local gettime = require"socket".gettime;

local archive = module:open_store("archive2", "archive");

-- Support both old and new MUC code
local mod_muc = module:depends"muc";
local rooms = rawget(mod_muc, "rooms");
local each_room = rawget(mod_muc, "each_room") or function() return it.values(rooms); end;
if not rooms then
	rooms = module:shared"muc/rooms";
end
local get_room_from_jid = rawget(mod_muc, "get_room_from_jid") or
	function (jid)
		return rooms[jid];
	end

local function get_room(name)
	local jid = name .. '@' .. module.host;
	return get_room_from_jid(jid);
end

module:depends"http";

local function template(data)
	local _doc = [[
	Like util.template, but deals with plain text
	Returns a closure that is called with a table of values
	{name} is substituted for values["name"] and is XML escaped
	{name!} is substituted without XML escaping
	{name?} is optional and is replaced with an empty string if no value exists
	]]
	return function(values)
		return (data:gsub("{([^!}]-)(%p?)}", function (name, opt)
			local value = values[name];
			if value then
				if opt ~= "!" then
					return st.xml_escape(value);
				end
				return value;
			elseif opt == "?" then
				return "";
			end
		end));
	end
end

local base = template[[
<!DOCTYPE html>
<meta charset="utf-8">
<title>{title}</title>
<style>
body { margin: 1ex 1em; }
ul { padding: 0; }
li.action dt, li.action dd { display: inline-block; margin-left: 0;}
li.action dd { margin-left: 1ex;}
li { list-style: none; }
li:hover { background: #eee; }
li time { float: right; font-size: small; opacity: 0.2; }
li:hover time { opacity: 1; }
li.join , li.leave { color: green; }
li.join dt, li.leave dt { color: green; }
nav { font-size: x-large; margin: 1ex 2em; }
nav a { text-decoration: none; }
</style>
<h1>{title}</h1>
{body!}
]]

local dates_template = template(base{
	title = "Logs for room {room}";
	body = [[
	<base href="{room}/">
	<nav>
	<a href="..">↑</a>
	</nav>
	<ul>
	{lines!}</ul>
	]];
})

local date_line_template = template[[
<li><a href="{date}">{date}</a></li>
]];

local page_template = template(base{
	title = "Logs for room {room} on {date}";
	body = [[
	<nav>
	<a class="prev" href="{prev}">←</a>
	<a class="up" href="../{room}">↑</a>
	<a class="next" href="{next}">→</a>
	</nav>
	<ul>
	{logs!}
	</ul>
	]];
});

local line_templates = {
	["message<groupchat"] = template[[
	<li id="{key}" class="{st_name}"><a href="#{key}"><time>{time}</time></a><dl><dt>{nick}</dt><dd>{body}</dd></dl></li>
	]];
	["message<groupchat<subject"] = template[[
	<li id="{key}" class="{st_name} action subject"><a href="#{key}"><time>{time}</time></a><dl><dt>{nick}</dt><dd>changed subject to {subject}</dd></dl></li>
	]];
	["presence"] = template[[
	<li id="{key}" class="action join"><a href="#{key}"><time>{time}</time></a><dl><dt>{nick}</dt><dd>joined</dd></dl></li>
	]];
	["presence<unavailable"] = template[[
	<li id="{key}" class="action leave"><a href="#{key}"><time>{time}</time></a><dl><dt>{nick}</dt><dd>left</dd></dl></li>
	]];
};

local room_list_template = template(base{
	title = "Rooms on {host}";
	body = [[
	<dl>
	{rooms!}
	</dl>
	]];
});

local room_item_template = template[[
<dt><a href="{room}">{name}</a></dt>
<dd>{description?}</dd>
]];

local function public_room(room)
	if type(room) == "string" then
		room = get_room(room);
	end
	return room and not room:get_hidden() and not room:get_members_only() and room._data.logging ~= false;
end

-- FIXME Invent some more efficient API for this
local function dates_page(event, room)
	local request, response = event.request, event.response;

	room = nodeprep(room);
	if not room or not public_room(room) then return end

	local dates, i = {}, 1;
	module:log("debug", "Find all dates with messages");
	local next_day;
	repeat
		local iter = archive:find(room, {
			["start"] = next_day;
			limit = 1;
		})
		if not iter then break end
		next_day = nil;
		for key, message, when in iter do
			next_day = datetime.date(when);
			dates[i], i = date_line_template{
				date = next_day;
			}, i + 1;
			next_day = datetime.parse(next_day .. "T23:59:59Z") + 1;
			break;
		end
	until not next_day;

	return dates_template{
		room = room;
		lines = table.concat(dates);
	};
end

local function logs_page(event, path)
	local request, response = event.request, event.response;

	local room, date = path:match("^(.-)/(%d%d%d%d%-%d%d%-%d%d)$");
	room = nodeprep(room);
	if not room then
		return dates_page(event, path);
	end
	if not public_room(room) then return end

	local logs, i = {}, 1;
	local iter, err = archive:find(room, {
		["start"] = datetime.parse(date.."T00:00:00Z");
		["end"]   = datetime.parse(date.."T23:59:59Z");
		limit = math.huge;
		-- with = "message<groupchat";
	});
	if not iter then return 500; end

	local templ, typ;
	for key, message, when in iter do
		templ = message.name;
		local typ = message.attr.type;
		if typ then templ = templ .. '<' .. typ; end
		local subject = message:get_child_text("subject");
		if subject then templ = templ .. '<subject'; end
		templ = line_templates[templ];
		if templ then
			logs[i], i = templ { 
				key = key;
				time = datetime.time(when);
				nick = select(3, jid_split(message.attr.from));
				body = message:get_child_text("body");
				subject = subject;
				st_name = message.name;
				st_type = message.attr.type;
			}, i + 1;
		else
			module:log("debug", "No template for %s", tostring(message));
		end
	end

	local next_when = datetime.parse(date.."T12:00:00Z") + 86400;
	local prev_when = datetime.parse(date.."T12:00:00Z") - 86400;

	module:log("debug", "Find next date with messages");
	for key, message, when in archive:find(room, {
		["start"] = datetime.parse(date.."T00:00:00Z") + 86401;
		limit = math.huge;
	}) do
	next_when = when;
	module:log("debug", "Next message: %s", datetime.datetime(when));
	break;
end

module:log("debug", "Find prev date with messages");
for key, message, when in archive:find(room, {
	["end"] = datetime.parse(date.."T00:00:00Z") - 1;
	limit = math.huge;
	reverse = true;
}) do
prev_when = when;
module:log("debug", "Previous message: %s", datetime.datetime(when));
break;
	end

	return page_template{
		room = room;
		date = date;
		logs = table.concat(logs);
		next = datetime.date(next_when);
		prev = datetime.date(prev_when);
	};
end

local function list_rooms(event)
	local room_list, i = {}, 1;
	for room in each_room() do
		if public_room(room) then
			room_list[i], i = room_item_template {
				room = jid_split(room.jid);
				name = room:get_name();
				description = room:get_description();
				subject = room:get_subject();
			}, i + 1;
		end
	end
	return room_list_template {
		host = module.host;
		rooms = table.concat(room_list);
	};
end

local cache = setmetatable({}, {__mode = 'v'});

local function with_cache(f)
	return function (event, path)
		local request, response = event.request, event.response;
		local ckey = path or "";
		local cached = cache[ckey];

		if cached then
			local etag = cached.etag;
			local if_none_match = request.headers.if_none_match;
			if etag == if_none_match then
				module:log("debug", "Client cache hit");
				return 304;
			end
			module:log("debug", "Server cache hit");
			response.headers.etag = etag;
			return cached[1];
		end

		local start = gettime();
		local render = f(event, path);
		module:log("debug", "Rendering took %dms", math.floor( (gettime() - start) * 1000 + 0.5));

		if type(render) == "string" then
			local etag = uuid();
			cached = { render, etag = etag, date = datetime.date() };
			response.headers.etag = etag;
			cache[ckey] = cached;
		end

		return render;
	end
end

-- How is cache invalidation a hard problem? ;)
module:hook("muc-broadcast-message", function (event)
	local room = event.room;
	local room_name = jid_split(room.jid);
	local today = datetime.date();
	cache[ room_name .. "/" .. today ] = nil;
	if cache[room_name] and cache[room_name].date ~= today then
		cache[room_name] = nil;
	end
end);

module:log("info", module:http_url());
module:provides("http", {
	route = {
		["GET /"] = list_rooms;
		["GET /*"] = with_cache(logs_page);
	};
});

