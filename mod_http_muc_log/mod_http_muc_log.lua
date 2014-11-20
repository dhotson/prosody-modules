local st = require "util.stanza";
local datetime = require"util.datetime";
local jid_split = require"util.jid".split;
local nodeprep = require"util.encodings".stringprep.nodeprep;
local uuid = require"util.uuid".generate;
local it = require"util.iterators";
local gettime = require"socket".gettime;

local archive = module:open_store("muc_log", "archive");

-- Support both old and new MUC code
local mod_muc = module:depends"muc";
local rooms = rawget(mod_muc, "rooms");
local each_room = rawget(mod_muc, "each_room") or function() return it.values(rooms); end;
local new_muc = not rooms;
if new_muc then
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
	--[[ DOC
	Like util.template, but deals with plain text
	Returns a closure that is called with a table of values
	{name} is substituted for values["name"] and is XML escaped
	{name!} is substituted without XML escaping
	{name?} is optional and is replaced with an empty string if no value exists
	]]
	return function(values)
		return (data:gsub("{([^}]-)(%p?)}", function (name, opt)
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

-- TODO Move templates into files
local base = template(template[[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="canonical" href="{canonical}">
<title>{title}</title>
<style>
body{background-color:#eeeeec;margin:1ex 0;padding-bottom:3em;font-family:Arial,Helvetica,sans-serif;}
header,footer{margin:1ex 1em;}
footer{font-size:smaller;color:#babdb6;}
.content{background-color:white;padding:1em;list-style-position:inside;}
nav{font-size:large;margin:1ex 1ex;clear:both;line-height:1.5em;}
nav a{padding: 1ex;text-decoration:none;}
nav a.up{font-size:smaller;}
nav a.prev{float:left;}
nav a.next{float:right;}
nav a.next::after{content:" →";}
nav a.prev::before{content:"← ";}
nav a:empty::after,nav a:empty::before{content:""}
@media screen and (min-width: 460px) {
nav{font-size:x-large;margin:1ex 1em;}
}
a:link,a:visited{color:#2e3436;text-decoration:none;}
a:link:hover,a:visited:hover{color:#3465a4;}
ul,ol{padding:0;}
li{list-style:none;}
hr{visibility:hidden;clear:both;}
br{clear:both;}
li time{float:right;font-size:small;opacity:0.2;}
li:hover time{opacity:1;}
.room-list .description{font-size:smaller;}
q.body::before,q.body::after{content:"";}
.presence .verb{font-style:normal;color:#30c030;}
.presence.unavailable .verb{color:#c03030;}
</style>
</head>
<body>
<header>
<h1>{title}</h1>
{header!}
</header>
<hr>
<div class="content">
{body!}
</div>
<hr>
<footer>
{footer!}
<br>
<div class="powered-by">Prosody {prosody_version?}</div>
</footer>
</body>
</html>
]] { prosody_version = prosody.version });

local dates_template = template(base{
	title = "Logs for room {room}";
	header = [[
<nav>
<a href=".." class="up">Back to room list</a>
</nav>
]];
	body = [[
<nav>
<ul class="dates">
{lines!}</ul>
</nav>
]];
	footer = "";
})

local date_line_template = template[[
<li><a href="{date}">{date}</a></li>
]];

local page_template = template(base{
	title = "Logs for room {room} on {date}";
	header = [[
<nav>
<a class="up" href=".">Back to date list</a>
<br>
<a class="prev" href="{prev}">{prev}</a>
<a class="next" href="{next}">{next}</a>
</nav>
]];
	body = [[
<ol class="chat-logs">
{logs!}</ol>
]];
	footer = [[
<nav>
<div>
<a class="prev" href="{prev}">{prev}</a>
<a class="next" href="{next}">{next}</a>
</div>
</nav>
<script>
/*
 * Local timestamps
 */
(function () {
	var timeTags = document.getElementsByTagName("time");
	var i = 0, tag, date;
	while(timeTags[i]) {
		tag = timeTags[i++];
		if(date = tag.getAttribute("datetime")) {
			date = new Date(date);
			tag.textContent = date.toLocaleTimeString();
			tag.setAttribute("title", date.toString());
		}
	}
})();
</script>
]];
});

local line_template = template[[
<li class="{st_name} {st_type?}" id="{key}">
	<span class="time">
		<a href="#{key}"><time datetime="{datetime}">{time}</time></a>
	</span>
	<b class="nick">{nick}</b>
	<em class="verb">{verb?}</em>
	<q class="body">{body?}</q>
</li>
]];

local room_list_template = template(base{
	title = "Rooms on {host}";
	header = "";
	body = [[
<nav>
<dl class="room-list">
{rooms!}
</dl>
</nav>
]];
	footer = "";
});

local room_item_template = template[[
<dt class="name"><a href="{room}/">{name}</a></dt>
<dd class="description">{description?}</dd>
]];

local function public_room(room)
	if type(room) == "string" then
		room = get_room(room);
	end
	return (room
		and not (room.get_hidden or room.is_hidden)(room)
		and not (room.get_members_only or room.is_members_only)(room)
		and room._data.logging ~= false);
end

-- FIXME Invent some more efficient API for this
local function dates_page(event, path)
	local request, response = event.request, event.response;

	local room = nodeprep(path:match("^(.*)/$"));
	if not room or not public_room(room) then return end

	local dates, i = {}, 1;
	module:log("debug", "Find all dates with messages");
	local next_day;
	repeat
		local iter = archive:find(room, {
			["start"] = next_day;
			limit = 1;
			with = "message<groupchat";
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

	response.headers.content_type = "text/html";
	return dates_template{
		host = module.host;
		canonical = module:http_url() .. "/" .. path;
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
		-- with = "message<groupchat";
	});
	if not iter then return 500; end

	local first, last;
	local verb, subject, body;
	for key, item, when in iter do
		body = item:get_child_text("body");
		subject = item:get_child_text("subject");
		verb = nil;
		if subject then
			verb = "set the topic to";
		elseif body and body:sub(1,4) == "/me " then
			verb, body = body:sub(5), nil;
		elseif item.name == "presence" then
			verb = item.attr.type == "unavailable" and "has left" or "has joined";
		end
		logs[i], i = line_template { 
			key = key;
			datetime = datetime.datetime(when);
			time = datetime.time(when);
			verb = verb;
			body = subject or body;
			nick = select(3, jid_split(item.attr.from));
			st_name = item.name;
			st_type = item.attr.type;
		}, i + 1;
		first = first or key;
		last = key;
	end
	if i == 1 then return end -- No items

	local next_when = "";
	local prev_when = "";

	module:log("debug", "Find next date with messages");
	for key, message, when in archive:find(room, {
		after = last;
		limit = 1;
	}) do
		next_when = datetime.date(when);
		module:log("debug", "Next message: %s", datetime.datetime(when));
	end

	module:log("debug", "Find prev date with messages");
	for key, message, when in archive:find(room, {
		before = first;
		limit = 1;
		reverse = true;
	}) do
		prev_when = datetime.date(when);
		module:log("debug", "Previous message: %s", datetime.datetime(when));
	end

	response.headers.content_type = "text/html";
	return page_template{
		canonical = module:http_url() .. "/" .. path;
		host = module.host;
		room = room;
		date = date;
		logs = table.concat(logs);
		next = next_when;
		prev = prev_when;
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
			}, i + 1;
		end
	end

	event.response.headers.content_type = "text/html";
	return room_list_template {
		host = module.host;
		canonical = module:http_url() .. "/";
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
			response.headers.content_type = "text/html";
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

		response.headers.content_type = "text/html";
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

