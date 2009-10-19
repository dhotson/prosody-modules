-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--
local prosody = prosody;
local splitJid = require "util.jid".split;
local bareJid = require "util.jid".bare;
local config_get = require "core.configmanager".get;
local httpserver = require "net.httpserver";
local serialize = require "util.serialization".serialize;
local config = {};


--[[ LuaFileSystem 
* URL: http://www.keplerproject.org/luafilesystem/index.html
* Install: luarocks install luafilesystem
* ]]
local lfs = require "lfs";

local lom = require "lxp.lom";


--[[
* Default templates for the html output.
]]--
local html = {};
html.doc = [[<html>
<head>
	<title>muc_log</title>
</head>
<style type="text/css">
<!--
.timestuff {color: #AAAAAA; text-decoration: none;}
.muc_join {color: #009900; font-style: italic;}
.muc_leave {color: #009900; font-style: italic;}
.muc_statusChange {color: #009900; font-style: italic;}
.muc_title {color: #009900;}
.muc_titlenick {color: #009900; font-style: italic;}
.muc_kick {color: #009900; font-style: italic;}
.muc_bann {color: #009900; font-style: italic;}
.muc_name {color: #0000AA;}
//-->
</style>
<body>
###BODY_STUFF###
</body>
</html>]];

html.hosts = {};
html.hosts.bit = [[<a href="/muc_log/###JID###">###JID###</a><br />]]
html.hosts.body = [[<h2>Rooms hosted on this server:</h2><hr /><p>
###HOSTS_STUFF###
</p><hr />]];

html.days = {};
html.days.bit = [[<a href="/muc_log/###JID###/?year=###YEAR###&month=###MONTH###&day=###DAY###">20###YEAR###/###MONTH###/###DAY###</a><br />]];
html.days.body = [[<h2>available logged days of room: ###JID###</h2><hr /><p>
###DAYS_STUFF###
</p><hr />]];

html.day = {};
html.day.time = [[<a name="###TIME###" href="####TIME###" class="timestuff">[###TIME###]</a> ]]; -- the one ####TIME### need to stay! it will evaluate to e.g. #09:10:56 which is an anker then
html.day.presence = {};
html.day.presence.join = [[###TIME_STUFF###<font class="muc_join"> *** ###NICK### joins the room</font><br />]];
html.day.presence.leave = [[###TIME_STUFF###<font class="muc_leave"> *** ###NICK### leaves the room</font><br />]];
html.day.presence.statusChange = [[###TIME_STUFF###<font class="muc_statusChange"> *** ###NICK### changed his/her status to: ###STATUS###</font><br />]];
html.day.message = [[###TIME_STUFF###<font class="muc_name">&lt;###NICK###&gt;</font> ###MSG###<br />]];
html.day.titleChange = [[###TIME_STUFF###<font class="muc_titlenick"> *** ###NICK### change title to:</font> <font class="muc_title">###MSG###</font><br />]];
html.day.kick = [[###TIME_STUFF###<font class="muc_titlenick"> *** ###NICK### kicked ###VICTIM###</font><br />]];
html.day.bann = [[###TIME_STUFF###<font class="muc_titlenick"> *** ###NICK### banned ###VICTIM###</font><br />]];
html.day.body = [[<h2>room ###JID### logging of 20###YEAR###/###MONTH###/###DAY###</h2><hr /><p>
###DAY_STUFF###
</p><hr />]];

html.help = [[
MUC logging is not configured correctly.<br />
Here is a example config:<br />
Component "rooms.example.com" "muc"<br />
&nbsp;&nbsp;modules_enabled = {<br />
&nbsp;&nbsp;&nbsp;&nbsp;"muc_log";<br />
&nbsp;&nbsp;}<br />
&nbsp;&nbsp;muc_log = {<br />
&nbsp;&nbsp;&nbsp;&nbsp;folder = "/opt/local/var/log/prosody/rooms";<br />
&nbsp;&nbsp;&nbsp;&nbsp;http_port = "/opt/local/var/log/prosody/rooms";<br />
&nbsp;&nbsp;}<br />
]];

function validateLogFolder()
	if config.folder == nil then
		module:log("warn", "muc_log folder isn't configured. configure it please!");
		return false;
	end

	-- check existance
	local attributes = lfs.attributes(config.folder);
	if attributes == nil then
		module:log("warn", "muc_log folder doesn't exist. create it please!");
		return false;
	elseif attributes.mode ~= "directory" then
		module:log("warn", "muc_log folder isn't a folder, it's a %s. change this please!", attributes.mode);
		return false;
	end --TODO: check for write rights!

	return true;
end

function logIfNeeded(e)
	local stanza, origin = e.stanza, e.origin;
	if validateLogFolder() == false then
		return;
	end
	
	if	(stanza.name == "presence") or 
	   	(stanza.name == "message" and tostring(stanza.attr.type) == "groupchat")
	then
		local node, host, resource = splitJid(stanza.attr.to);
		if node ~= nil and host ~= nil then
			local bare = node .. "@" .. host;
			if prosody.hosts[host] ~= nil and prosody.hosts[host].muc ~= nil and prosody.hosts[host].muc.rooms[bare] ~= nil then
				local room = prosody.hosts[host].muc.rooms[bare]
				local today = os.date("%y%m%d");
				local now = os.date("%X")
				local fn = config.folder .. "/" .. today .. "_" .. bare .. ".log";
				local mucFrom = nil;
		
				if stanza.name == "presence" and stanza.attr.type == nil then
					mucFrom = stanza.attr.to;
				else
					for jid, nick in pairs(room._jid_nick) do
						if jid == stanza.attr.from then
							mucFrom = nick;
						end
					end
				end

				if mucFrom ~= nil then
					module:log("debug", "try to open room log: %s", fn);
					local f = assert(io.open(fn, "a"));
					local realFrom = stanza.attr.from;
					local realTo = stanza.attr.to;
					stanza.attr.from = mucFrom;
					stanza.attr.to = nil;
					f:write("<stanza time=\"".. now .. "\">" .. tostring(stanza) .. "</stanza>\n");
					stanza.attr.from = realFrom;
					stanza.attr.to = realTo;
					f:close()
				end
			end
		end
	end
	return;
end

function createDoc(body)
	return html.doc:gsub("###BODY_STUFF###", body);
end

local function htmlEscape(t)
	t = t:gsub("\n", "<br />");
	-- TODO link text into klickable link and such stuff
	return t;
end

function splitQuery(query)
	local ret = {};
	if query == nil then return ret; end
	local last = 1;
	local idx = query:find("&", last);
	while idx ~= nil do
		ret[#ret + 1] = query:sub(last, idx - 1);
		last = idx + 1;
		idx = query:find("&", last);
	end
	ret[#ret + 1] = query:sub(last);
	return ret;
end

function grepRoomJid(url)
	local tmp = url:sub(string.len("/muc_log/") + 1);
	local node = nil;
	local host = nil;
	local at = nil;
	local slash = nil;
	
	at = tmp:find("@");
	slash = tmp:find("/");
	if slash ~= nil then
		slash = slash - 1;
	end
	
	if at ~= nil then
	 	node = tmp:sub(1, at - 1);
		host = tmp:sub(at + 1, slash);
	end
	return node, host;
end

local function generateRoomListSiteContent()
	local rooms = "";
	for host, config in pairs(prosody.hosts) do
		if prosody.hosts[host].muc ~= nil then
			for jid, room in pairs(prosody.hosts[host].muc.rooms) do
				rooms = rooms .. html.hosts.bit:gsub("###JID###", jid);
			end
		end
	end
	
	return html.hosts.body:gsub("###HOSTS_STUFF###", rooms);
end

local function generateDayListSiteContentByRoom(bareRoomJid)
	local days = "";
	local tmp;

	for file in lfs.dir(config.folder) do
		local year, month, day = file:match("^(%d%d)(%d%d)(%d%d)_" .. bareRoomJid .. ".log");
		if	year ~= nil and month ~= nil and day ~= nil and
			year ~= ""  and month ~= ""  and day ~= ""
		then
			tmp = html.days.bit;
			tmp = tmp:gsub("###JID###", bareRoomJid);
			tmp = tmp:gsub("###YEAR###", year);
			tmp = tmp:gsub("###MONTH###", month);
			tmp = tmp:gsub("###DAY###", day);
			days = tmp .. days;
		end
	end
	if days ~= "" then
		tmp = html.days.body:gsub("###DAYS_STUFF###", days);
		return tmp:gsub("###JID###", bareRoomJid);
	else
		return generateRoomListSiteContent(); -- fallback
	end
end

local function parseDay(bareRoomJid, query)
	local ret = "";
	local year;
	local month;
	local day;
	local tmp;
	
	for _,str in ipairs(query) do 
		local name, value;
		name, value = str:match("^(%a+)=(%d+)$");
		if name == "year" then
			year = value;
		elseif name == "month" then
			month = value;
		elseif name == "day" then
			day = value;
		else
			log("warn", "unknown query value");
		end
	end
	
	if year ~= nil and month ~= nil and day ~= nil then
		local file = config.folder .. "/" .. year .. month .. day .. "_" .. bareRoomJid .. ".log";
		local f, err = io.open(file, "r");
		if f ~= nil then
			local content = f:read("*a");
			local parsed = lom.parse("<xml>" .. content .. "</xml>");
			if parsed ~= nil then
				for _,stanza in ipairs(parsed) do
					if stanza.attr ~= nil and stanza.attr.time ~= nil then
						local timeStuff = html.day.time:gsub("###TIME###", stanza.attr.time);
						if stanza[1] ~= nil then
							local nick;
							
							-- grep nick from "from" resource
							if stanza[1].attr.from ~= nil then
								nick = stanza[1].attr.from:match("/(.+)$");
							end
							
							if stanza[1].tag == "presence" and nick ~= nil then
								
								if stanza[1].attr.type == nil then
									tmp = html.day.presence.join:gsub("###TIME_STUFF###", timeStuff);
									ret = ret .. tmp:gsub("###NICK###", nick);
								elseif stanza[1].attr.type ~= nil and stanza[1].attr.type == "unavailable" then
									tmp = html.day.presence.leave:gsub("###TIME_STUFF###", timeStuff);
									ret = ret .. tmp:gsub("###NICK###", nick);
								else
									tmp = html.day.presence.leave:gsub("###TIME_STUFF###", timeStuff);
									tmp = tmp:gsub("###STATUS###", stanza[1].attr.type);
									ret = ret .. tmp:gsub("###NICK###", nick);
								end
							elseif stanza[1].tag == "message" then
								local body;
								for _,tag in ipairs(stanza[1]) do
									if tag.tag == "body" then
										body = htmlEscape(tag[1]);
										if nick ~= nil then
											break;
										end
									elseif tag.tag == "nick" and nick == nil then
										nick = tag[1];
										if body ~= nil then
											break;
										end
									end
								end
								if nick ~= nil and body ~= nil then
									tmp = html.day.message:gsub("###TIME_STUFF###", timeStuff);
									tmp = tmp:gsub("###NICK###", nick);
									ret = ret .. tmp:gsub("###MSG###", body);
								end
							else
								module:log("info", "unknown stanza subtag in log found. room: %s; day: %s", bareRoomJid, year .. "/" .. month .. "/" .. day);
							end
						end
					end
				end
			else
					module:log("warn", "could not parse room log. room: %s; day: %s", bareRoomJid, year .. "/" .. month .. "/" .. day);
			end
			f:close();
		else
			ret = err;
		end
		tmp = html.day.body:gsub("###DAY_STUFF###", ret);
		tmp = tmp:gsub("###JID###", bareRoomJid);
		tmp = tmp:gsub("###YEAR###", year);
		tmp = tmp:gsub("###MONTH###", month);
		tmp = tmp:gsub("###DAY###", day);
		return tmp;
	else
		return generateDayListSiteContentByRoom(bareRoomJid); -- fallback
	end
end

function handle_request(method, body, request)
	module:log("debug", "got a request ...")
	local query = splitQuery(request.url.query);
	local node, host = grepRoomJid(request.url.path);
	
	if validateLogFolder() == false then
		return createDoc(html.help);
	end
	if node ~= nil  and host ~= nil then
		local bare = node .. "@" .. host;
		if prosody.hosts[host] ~= nil and prosody.hosts[host].muc ~= nil and prosody.hosts[host].muc.rooms[bare] ~= nil then
			local room = prosody.hosts[host].muc.rooms[bare];
			if request.url.query == nil then
				return createDoc(generateDayListSiteContentByRoom(bare));
			else
				return createDoc(parseDay(bare, query));
			end
		else
			module:log("warn", "room instance not found. bare room jid: %s", tostring(bare));
		end
	else
		return createDoc(generateRoomListSiteContent());
	end
	return;
end

config = config_get(module:get_host(), "core", "muc_log");
module:log("debug", serialize(config));

httpserver.new_from_config({ config.http_port or true }, handle_request, { base = "muc_log" });

module:hook("message/bare", logIfNeeded, 500);
module:hook("pre-message/bare", logIfNeeded, 500);
module:hook("presence/full", logIfNeeded, 500);
module:hook("pre-presence/full", logIfNeeded, 500);
