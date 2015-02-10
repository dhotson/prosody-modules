local st = require "util.stanza";
local mt = require"util.multitable";
local datetime = require"util.datetime";
local jid_split = require"util.jid".split;
local nodeprep = require"util.encodings".stringprep.nodeprep;
local uuid = require"util.uuid".generate;
local it = require"util.iterators";
local gettime = require"socket".gettime;
local url = require"socket.url";
local xml_escape = st.xml_escape;
local t_concat = table.concat;
local os_time, os_date = os.time, os.date;

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

local function render(template, values)
	--[[ DOC
	{name} is substituted for values["name"] and is XML escaped
	{name!} is substituted without XML escaping
	{name?} is optional and is replaced with an empty string if no value exists
	{name# sub-template } renders a sub-template using an array of values
	]]
	return (template:gsub("%b{}", function (block)
		local name, opt, e = block:sub(2, -2):match("([%a_][%w_]*)(%p?)()");
		local value = values[name];
		if opt == '#' then
			if not value or not value[1] then return ""; end
			local out, subtpl = {}, block:sub(e+1, -2);
			for i=1, #value do
				out[i] = render(subtpl, value[i]);
			end
			return t_concat(out);
		end
		if value ~= nil  then
			if type(value) ~= "string" then
				value = tostring(value);
			end
			if opt ~= '!' then
				return xml_escape(value);
			end
			return value;
		elseif opt == '?' then
			return block:sub(e+1, -2);
		end
	end));
end

local template = "Could not load template"
do
	local template_file = module:get_option_string(module.name .. "_template", module.name .. ".html");
	template_file = assert(module:load_resource(template_file));
	template = template_file:read("*a");
	template_file:close();
end

local base_url = module:http_url() .. '/';
local get_link do
	local link, path = { path = '/' }, { "", "", is_directory = true };
	function get_link(room, date)
		path[1], path[2] = room, date;
		path.is_directory = not date;
		link.path = url.build_path(path);
		return url.build(link);
	end
end

local function public_room(room)
	if type(room) == "string" then
		room = get_room(room);
	end
	return (room
		and not (room.get_hidden or room.is_hidden)(room)
		and not (room.get_members_only or room.is_members_only)(room)
		and room._data.logging == true);
end

local function sort_Y(a,b) return a.year > b.year end
local function sort_m(a,b) return a.n > b.n end

local t_diff = os_time(os_date("*t")) - os_time(os_date("!*t"));
local function time(t)
	return os_time(t) + t_diff;
end

local function years_page(event, path)
	local request, response = event.request, event.response;

	local room = nodeprep(path:match("^(.*)/$"));
	if not room or not public_room(room) then return end

	local dates = mt.new();
	module:log("debug", "Find all dates with messages");
	local next_day, t;
	repeat
		local iter = archive:find(room, {
			start = next_day;
			limit = 1;
			with = "message<groupchat";
		})
		if not iter then break end
		next_day = nil;
		for key, message, when in iter do
			t = os_date("!*t", when);
			dates:set(t.year, t.month, t.day, when );
			next_day = when + (86400 - (when % 86400));
			break;
		end
	until not next_day;

	local year, years;
	local month, months;
	local week, weeks;
	local days;
	local tmp, n;

	years = {};

	for Y, m in pairs(dates.data) do
		t = { year = Y, month = 1, day = 1 };
		months = { };
		year = { year = Y, months = months };
		years[#years+1] = year;
		for m, d in pairs(m) do
			t.day = 1;
			t.month = m;
			tmp = os_date("!*t", time(t));
			days = {};
			week = { days = days }
			weeks = { week };
			month = { year = year.year, month = os_date("!%B", time(t)), n = m, weeks = weeks };
			months[#months+1] = month;
			n = 1;
			for i=1, (tmp.wday+5)%7 do
				days[n], n = {}, n+1;
			end
			for i = 1, 31 do
				t.day = i;
				tmp = os_date("!*t", time(t));
				if tmp.month ~= m then break end
				if i > 1 and tmp.wday == 2 then
					days = {};
					weeks[#weeks+1] = { days = days };
					n = 1;
				end
				if d[i] then
					days[n], n = { wday = tmp.wday, links = {{ href = datetime.date(d[i]), day = i }} }, n+1;
				else
					days[n], n = { wday = tmp.wday, plain = i }, n+1;
				end
			end
		end
		table.sort(year, sort_m);
	end
	table.sort(years, sort_Y);

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = get_room(room):get_name();
		jid = get_room(room).jid;
		years = years;
		links = {
			{ href = "../", rel = "up", text = "Back to room list" },
		};
	});
end

local function logs_page(event, path)
	local request, response = event.request, event.response;

	local room, date = path:match("^(.-)/(%d%d%d%d%-%d%d%-%d%d)$");
	room = nodeprep(room);
	if not room then
		return years_page(event, path);
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
			verb, body = "set the topic to", subject;
		elseif body and body:sub(1,4) == "/me " then
			verb, body = body:sub(5), nil;
		elseif item.name == "presence" then
			verb = item.attr.type == "unavailable" and "has left" or "has joined";
		end
		if body or verb then
			logs[i], i = {
				key = key;
				datetime = datetime.datetime(when);
				time = datetime.time(when);
				verb = verb;
				body = body;
				nick = select(3, jid_split(item.attr.from));
				st_name = item.name;
				st_type = item.attr.type;
			}, i + 1;
		end
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

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = ("%s - %s"):format(get_room(room):get_name(), date);
		jid = get_room(room).jid;
		lines = logs;
		links = {
			{ href = "./", rel = "up", text = "Back to calendar" },
			{ href = prev_when, rel = "prev", text = prev_when},
			{ href = next_when, rel = "next", text = next_when},
		};
	});
end

local function list_rooms(event)
	local request, response = event.request, event.response;
	local room_list, i = {}, 1;
	for room in each_room() do
		if public_room(room) then
			room_list[i], i = {
				href = get_link(jid_split(room.jid), nil);
				name = room:get_name();
				description = room:get_description();
			}, i + 1;
		end
	end

	response.headers.content_type = "text/html; charset=utf-8";
	return render(template, {
		title = module:get_option_string("name", "Prosody Chatrooms");
		jid = module.host;
		rooms = room_list;
	});
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
			response.headers.content_type = "text/html; charset=utf-8";
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

		response.headers.content_type = "text/html; charset=utf-8";
		return render;
	end
end

-- How is cache invalidation a hard problem? ;)
module:hook("muc-broadcast-message", function (event)
	local room = event.room;
	local room_name = jid_split(room.jid);
	local today = datetime.date();
	cache[get_link(room_name)] = nil;
	cache[get_link(room_name, today)] = nil;
end);

module:provides("http", {
	route = {
		["GET /"] = list_rooms;
		["GET /*"] = with_cache(logs_page);
	};
});

