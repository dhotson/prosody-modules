-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--
local prosody = prosody;
local tabSort = table.sort;
local splitJid = require "util.jid".split;
local bareJid = require "util.jid".bare;
local config_get = require "core.configmanager".get;
local httpserver = require "net.httpserver";
local serialize = require "util.serialization".serialize;
local datamanager = require "util.datamanager";
local data_load, data_store, data_getpath = datamanager.load, datamanager.store, datamanager.getpath;
local datastore = "muc_log";
local muc_hosts = {};
local config = nil;


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
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" >
<head>
	<title>muc_log</title>
</head>
<script type="text/javascript"><!--
function showHide(name) {
	var eles = document.getElementsByName(name);
	for (var i = 0; i < eles.length; i++) {
		eles[i].style.display = eles[i].style.display != "none" ? "none" : "";
	}
	
}
--></script>
<style type="text/css">
<!--
.timestuff {color: #AAAAAA; text-decoration: none;}
.muc_join {color: #009900; font-style: italic;}
.muc_leave {color: #009900; font-style: italic;}
.muc_statusChange {color: #009900; font-style: italic;}
.muc_title {color: #BBBBBB; font-size: 32px;}
.muc_titleChange {color: #009900; font-style: italic;}
.muc_kick {color: #009900; font-style: italic;}
.muc_bann {color: #009900; font-style: italic;}
.muc_msg_nick {color: #0000AA;}
//-->
</style>
<body>
###BODY_STUFF###
</body>
</html>]];

html.components = {};
html.components.bit = [[<a href="###COMPONENT###/">###COMPONENT###</a><br />]]
html.components.body = [[<h2>MUC hosts available on this server:</h2><hr /><p>
###COMPONENTS_STUFF###
</p><hr />]];

html.rooms = {};
html.rooms.bit = [[<a href="###ROOM###/">###ROOM###</a><br />]]
html.rooms.body = [[<h2>Rooms hosted on MUC host: ###COMPONENT###</h2><hr /><p>
###ROOMS_STUFF###
</p><hr />]];

html.days = {};
html.days.bit = [[<a href="###BARE_DAY###/">20###YEAR###/###MONTH###/###DAY###</a><br />]];
html.days.body = [[<h2>available logged days of room: ###JID###</h2><hr /><p>
###DAYS_STUFF###
</p><hr />]];

html.day = {};
html.day.title = [[Subject: <font class="muc_title">###TITLE###</font>]];
html.day.time = [[<a name="###TIME###" href="####TIME###" class="timestuff">[###TIME###]</a> ]]; -- the one ####TIME### need to stay! it will evaluate to e.g. #09:10:56 which is an anker then
html.day.presence = {};
html.day.presence.join = [[<div name="joinLeave" style="display: ###SHOWHIDE###;">###TIME_STUFF###<font class="muc_join"> *** ###NICK### joins the room</font><br /></div>]];
html.day.presence.leave = [[<div name="joinLeave" style="display: ###SHOWHIDE###;">###TIME_STUFF###<font class="muc_leave"> *** ###NICK### leaves the room</font><br /></div>]];
html.day.presence.statusText = [[ and his status message is "###STATUS###"]];
html.day.presence.statusChange = [[<div name="status" style="display: ###SHOWHIDE###;">###TIME_STUFF###<font class="muc_statusChange"> *** ###NICK### shows now as "###SHOW###"###STATUS_STUFF###</font><br /></div>]];
html.day.message = [[###TIME_STUFF###<font class="muc_msg_nick">&lt;###NICK###&gt;</font> ###MSG###<br />]];
html.day.titleChange = [[###TIME_STUFF###<font class="muc_titleChange"> *** ###NICK### changed the title to "###TITLE###"</font><br />]];
html.day.reason = [[, the reason was "###REASON###"]]
html.day.kick = [[###TIME_STUFF###<font class="muc_kick"> *** ###VICTIM### got kicked###REASON_STUFF###</font><br />]];
html.day.bann = [[###TIME_STUFF###<font class="muc_bann"> *** ###VICTIM### got banned###REASON_STUFF###</font><br />]];
html.day.body = [[<h2>room ###JID### logging of 20###YEAR###/###MONTH###/###DAY###</h2>
<p>###TITLE_STUFF###</p>
<input type="checkbox" onclick="showHide('joinLeave')" ###JOIN_CHECKED###/>show/hide joins and Leaves</button>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
<input type="checkbox" onclick="showHide('status')" ###STATUS_CHECKED###/>show/hide status changes</button>
<hr /><div id="main" style="overflow: scroll;">
###DAY_STUFF###
</div><hr />
<script><!--
var ele = document.getElementById("main");
ele.style.height = window.innerHeight - ele.offsetTop - 25;
--></script>]];

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

local function ensureDatastorePathExists(node, host, today)
	local path = data_getpath(node, host, datastore, "dat", true);
	path = path:gsub("/[^/]*$", "");

	-- check existance
	local attributes, err = lfs.attributes(path);
	if attributes == nil or attributes.mode ~= "directory" then
		module:log("warn", "muc_log folder isn't a folder: %s", path);
		return false;
	end
	
	attributes, err = lfs.attributes(path .. "/" .. today);
	if attributes == nil then
		return lfs.mkdir(path .. "/" .. today);
	elseif attributes.mode == "directory" then
		return true;
	end
	return false;
end

function logIfNeeded(e)
	local stanza, origin = e.stanza, e.origin;
	
	if	(stanza.name == "presence") or
		(stanza.name == "iq") or
	   	(stanza.name == "message" and tostring(stanza.attr.type) == "groupchat")
	then
		local node, host, resource = splitJid(stanza.attr.to);
		if node ~= nil and host ~= nil then
			local bare = node .. "@" .. host;
			if muc_hosts[host] and prosody.hosts[host] ~= nil and prosody.hosts[host].muc ~= nil and prosody.hosts[host].muc.rooms[bare] ~= nil then
				local room = prosody.hosts[host].muc.rooms[bare]
				local today = os.date("%y%m%d");
				local now = os.date("%X")
				local mucTo = nil
				local mucFrom = nil;
				local alreadyJoined = false;
				
				if room._data.hidden then -- do not log any data of private rooms
					return;
				end
				
				if stanza.name == "presence" and stanza.attr.type == nil then
					mucFrom = stanza.attr.to;
					if room._occupants ~= nil and room._occupants[stanza.attr.to] ~= nil then -- if true, the user has already joined the room
						alreadyJoined = true;
						stanza:tag("alreadyJoined"):text("true"); -- we need to log the information that the user has already joined, so add this and remove after logging
					end
				elseif stanza.name == "iq" and stanza.attr.type == "set" then -- kick, to is the room, from is the admin, nick who is kicked is attr of iq->query->item
					if stanza.tags[1] ~= nil and stanza.tags[1].name == "query" then
						local tmp = stanza.tags[1];
						if tmp.tags[1] ~= nil and tmp.tags[1].name == "item" and tmp.tags[1].attr.nick ~= nil then
							tmp = tmp.tags[1];
							for jid, nick in pairs(room._jid_nick) do
								if nick == stanza.attr.to .. "/" .. tmp.attr.nick then
									mucTo = nick;
									break;
								end
							end
						end
					end
				else
					for jid, nick in pairs(room._jid_nick) do
						if jid == stanza.attr.from then
							mucFrom = nick;
							break;
						end
					end
				end

				if (mucFrom ~= nil or mucTo ~= nil) and ensureDatastorePathExists(node, host, today) then
					local data = data_load(node, host, datastore .. "/" .. today);
					local realFrom = stanza.attr.from;
					local realTo = stanza.attr.to;
					
					if data == nil then
						data = {};
					end
					
					stanza.attr.from = mucFrom;
					stanza.attr.to = mucTo;
					data[#data + 1] = "<stanza time=\"".. now .. "\">" .. tostring(stanza) .. "</stanza>\n";
					stanza.attr.from = realFrom;
					stanza.attr.to = realTo;
					if alreadyJoined == true then
						if stanza[#stanza].name == "alreadyJoined" then  -- normaly the faked element should be the last, remove it when it is the last
							stanza[#stanza] = nil;
						else
							for i = 1, #stanza, 1 do
								if stanza[i].name == "alreadyJoined" then  -- remove the faked element
									stanza[i] = nil;
									break;
								end
							end
						end
					end
					data_store(node, host, datastore .. "/" .. today, data);
				end
			end
		end
	end
	return;
end

function createDoc(body)
	return html.doc:gsub("###BODY_STUFF###", body or "");
end

local function htmlEscape(t)
	t = t:gsub("<", "&lt;");
	t = t:gsub(">", "&gt;");
	t = t:gsub("(http://[%a%d@%.:/&%?=%-_#]+)", [[<a href="%1">%1</a>]]);
	t = t:gsub("\n", "<br />");
	-- TODO do any html escaping stuff ... 
	return t;
end

function splitUrl(url)
	local tmp = url:sub(string.len("/muc_log/") + 1);
	local day = nil;
	local room = nil;
	local component = nil;
	local at = nil;
	local slash = nil;
	local slash2 = nil;
	
	slash = tmp:find("/");
	if slash then
	 	component = tmp:sub(1, slash - 1);
		if tmp:len() > slash then
			room = tmp:sub(slash + 1);
			slash = room:find("/");
			if slash then
				tmp = room;
				room = tmp:sub(1, slash - 1);
				if tmp:len() > slash then
					day = tmp:sub(slash + 1);
					slash = day:find("/");
					if slash then
						day = day:sub(1, slash - 1);
					end
				end
			end
		end
	end
	
	return room, component, day;
end

local function generateComponentListSiteContent()
	local components = "";
	for component,muc_host in pairs(muc_hosts) do
		components = components .. html.components.bit:gsub("###COMPONENT###", component);
	end
	
	return html.components.body:gsub("###COMPONENTS_STUFF###", components);
end

local function generateRoomListSiteContent(component)
	local rooms = "";
	if prosody.hosts[component] and prosody.hosts[component].muc ~= nil then
		for jid, room in pairs(prosody.hosts[component].muc.rooms) do
			local node = splitJid(jid);
			if not room._data.hidden and node then
				rooms = rooms .. html.rooms.bit:gsub("###ROOM###", node):gsub("###COMPONENT###", component);
			end
		end
		return html.rooms.body:gsub("###ROOMS_STUFF###", rooms):gsub("###COMPONENT###", component);
	end
	return generateComponentListSiteContent(); -- fallback
end

local function generateDayListSiteContentByRoom(bareRoomJid)
	local days = "";
	local arrDays = {};
	local tmp;
	local node, host, resource = splitJid(bareRoomJid);
	local path = data_getpath(node, host, datastore);
	local room = nil;
	local attributes = nil;
	
	path = path:gsub("/[^/]*$", "");
	attributes = lfs.attributes(path);
	if muc_hosts[host] and prosody.hosts[host] ~= nil and prosody.hosts[host].muc ~= nil and prosody.hosts[host].muc.rooms[bareRoomJid] ~= nil then
		room = prosody.hosts[host].muc.rooms[bareRoomJid];
		if room._data.hidden then
			room = nil
		end
	end
	if attributes ~= nil and room ~= nil then
		for file in lfs.dir(path) do
			local year, month, day = file:match("^(%d%d)(%d%d)(%d%d)");
			if	year ~= nil and month ~= nil and day ~= nil and
				year ~= ""  and month ~= ""  and day ~= ""
			then
					arrDays[#arrDays + 1] = {bare=file, year=year, month=month, day=day};
			end
		end
		tabSort(arrDays, function(a,b) 
			return a.bare < b.bare;
		end);
		for _, date in pairs(arrDays) do
			tmp = html.days.bit;
			tmp = tmp:gsub("###ROOM###", node):gsub("###COMPONENT###", host);
			tmp = tmp:gsub("###BARE_DAY###", date.bare);
			tmp = tmp:gsub("###YEAR###", date.year):gsub("###MONTH###", date.month):gsub("###DAY###", date.day);
			days = tmp .. days;
		end
	end
	
	if days ~= "" then
		tmp = html.days.body:gsub("###DAYS_STUFF###", days);
		return tmp:gsub("###JID###", bareRoomJid);
	else
		return generateRoomListSiteContent(host); -- fallback
	end
end

local function parseIqStanza(stanza, timeStuff, nick)
	local text = nil;
	local victim = nil;
	if(stanza.attr.type == "set") then
		for _,tag in ipairs(stanza) do
			if tag.tag == "query" then
				for _,item in ipairs(tag) do
					if item.tag == "item" and item.attr.nick ~= nil and tostring(item.attr.role) == 'none' then
						victim = item.attr.nick;
						for _,reason in ipairs(item) do
							if reason.tag == "reason" then
								text = reason[1];
								break;
							end
						end
						break;
					end 
				end
				break;
			end
		end
		if victim ~= nil then
			if text ~= nil then	
				text = html.day.reason:gsub("###REASON###", htmlEscape(text));
			else
				text = "";
			end	
			return html.day.kick:gsub("###TIME_STUFF###", timeStuff):gsub("###VICTIM###", victim):gsub("###REASON_STUFF###", text);
		end
	end
	return;
end

local function parsePresenceStanza(stanza, timeStuff, nick)
	local ret = "";
	local showJoin = "block"
	
	if config and not config.showJoin then
		showJoin = "none";
	end

	if stanza.attr.type == nil then
		local showStatus = "block"
		if config and not config.showStatus then
			showStatus = "none";
		end
		local show, status = nil, "";
		local alreadyJoined = false;
		for _, tag in ipairs(stanza) do
			if tag.tag == "alreadyJoined" then
				alreadyJoined = true;
			elseif tag.tag == "show" then
				show = tag[1];
			elseif tag.tag == "status" then
				status = tag[1];
			end
		end
		if alreadyJoined == true then
			if show == nil then
				show = "online";
			end
			ret = html.day.presence.statusChange:gsub("###TIME_STUFF###", timeStuff);
			if status ~= "" then
				status = html.day.presence.statusText:gsub("###STATUS###", htmlEscape(status));
			end
			ret = ret:gsub("###SHOW###", show):gsub("###NICK###", nick):gsub("###SHOWHIDE###", showStatus):gsub("###STATUS_STUFF###", status);
		else
			ret = html.day.presence.join:gsub("###TIME_STUFF###", timeStuff):gsub("###SHOWHIDE###", showJoin):gsub("###NICK###", nick);
		end
	elseif stanza.attr.type ~= nil and stanza.attr.type == "unavailable" then

		ret = html.day.presence.leave:gsub("###TIME_STUFF###", timeStuff):gsub("###SHOWHIDE###", showJoin):gsub("###NICK###", nick);
	end
	return ret;
end

local function parseMessageStanza(stanza, timeStuff, nick)
	local body, title, ret = nil, nil, "";
	
	for _,tag in ipairs(stanza) do
		if tag.tag == "body" then
			body = tag[1];
			if nick ~= nil then
				break;
			end
		elseif tag.tag == "nick" and nick == nil then
			nick = htmlEscape(tag[1]);
			if body ~= nil or title ~= nil then
				break;
			end
		elseif tag.tag == "subject" then
			title = tag[1];
			if nick ~= nil then
				break;
			end
		end
	end
	if nick ~= nil and body ~= nil then
		body = htmlEscape(body);
		ret = html.day.message:gsub("###TIME_STUFF###", timeStuff):gsub("###NICK###", nick):gsub("###MSG###", body);
	elseif nick ~= nil and title ~= nil then
		title = htmlEscape(title);
		ret = html.day.titleChange:gsub("###TIME_STUFF###", timeStuff):gsub("###NICK###", nick):gsub("###TITLE###", title);	
	end
	return ret;
end

local function parseDay(bareRoomJid, roomSubject, bare_day)
	local ret = "";
	local year;
	local month;
	local day;
	local tmp;
	local node, host, resource = splitJid(bareRoomJid);
	local year, month, day = bare_day:match("^(%d%d)(%d%d)(%d%d)");
	
	if bare_day ~= nil then
		local data = data_load(node, host, datastore .. "/" .. bare_day);
		if data ~= nil then
			for i=1, #data, 1 do
				local stanza = lom.parse(data[i]);
				if stanza ~= nil and stanza.attr ~= nil and stanza.attr.time ~= nil then
					local timeStuff = html.day.time:gsub("###TIME###", stanza.attr.time);
					if stanza[1] ~= nil then
						local nick;
						local tmp;
						
						-- grep nick from "from" resource
						if stanza[1].attr.from ~= nil then -- presence and messages
							nick = htmlEscape(stanza[1].attr.from:match("/(.+)$"));
						elseif stanza[1].attr.to ~= nil then -- iq
							nick = htmlEscape(stanza[1].attr.to:match("/(.+)$"));
						end
						
						if stanza[1].tag == "presence" and nick ~= nil then
							tmp = parsePresenceStanza(stanza[1], timeStuff, nick);
						elseif stanza[1].tag == "message" then
							tmp = parseMessageStanza(stanza[1], timeStuff, nick);
						elseif stanza[1].tag == "iq" then
							tmp = parseIqStanza(stanza[1], timeStuff, nick);
						else
							module:log("info", "unknown stanza subtag in log found. room: %s; day: %s", bareRoomJid, year .. "/" .. month .. "/" .. day);
						end
						if tmp ~= nil then
							ret = ret .. tmp
							tmp = nil;
						end
					end
				end
			end
		else
			return generateDayListSiteContentByRoom(bareRoomJid); -- fallback
		end
		tmp = html.day.body:gsub("###DAY_STUFF###", ret):gsub("###JID###", bareRoomJid);
		tmp = tmp:gsub("###YEAR###", year):gsub("###MONTH###", month):gsub("###DAY###", day);
		tmp = tmp:gsub("###TITLE_STUFF###", html.day.title:gsub("###TITLE###", roomSubject));
		tmp = tmp:gsub("###STATUS_CHECKED###", config.showStatus and "checked='checked'" or "");
		tmp = tmp:gsub("###JOIN_CHECKED###", config.showJoin and "checked='checked'" or "");
		return tmp;
	else
		return generateDayListSiteContentByRoom(bareRoomJid); -- fallback
	end
end

--[[
local function loggingMucComponents()
	local n = 0;
	for component,_ in pairs(muc_hosts) do
		n = n + 1;
	end
	return n;
end
]]--

function handle_request(method, body, request)
	-- local query = splitQuery(request.url.query);
	local node, host, day = splitUrl(request.url.path);
	--[[if host == nil and loggingMucComponents() == 1 then
		for component,_ in pairs(muc_hosts) do
			host = component;
			break;
		end
		module:log("debug", "host: %s", tostring(host));
	end]]--
	
	if node ~= nil and host ~= nil then
		local bare = node .. "@" .. host;
		if prosody.hosts[host] ~= nil and prosody.hosts[host].muc ~= nil then
			if prosody.hosts[host].muc.rooms[bare] ~= nil then
				local room = prosody.hosts[host].muc.rooms[bare];
				if day == nil then
					return createDoc(generateDayListSiteContentByRoom(bare));
				else
					local subject = ""
					if room._data ~= nil and room._data.subject ~= nil then
						subject = room._data.subject;
					end
					return createDoc(parseDay(bare, subject, day));
				end
			else
				return createDoc(generateRoomListSiteContent(host));
			end
		else
			return createDoc(generateComponentListSiteContent());
		end
	elseif host ~= nil then
		return createDoc(generateRoomListSiteContent(host));
	else
		return createDoc(generateComponentListSiteContent());
	end
	return;
end

function module.load()
	config = config_get("*", "core", "muc_log") or {};
	if config.showStatus == nil then
		config.showStatus = true;
	end
	if config.showJoin == nil then
		config.showJoin = true;
	end
	httpserver.new_from_config({ config.http_port or true }, handle_request, { base = "muc_log" });
	
	for jid, host in pairs(prosody.hosts) do
		if host.muc then
			local logging = config_get(jid, "core", "logging");
			if logging then
				module:log("debug", "component: %s", tostring(jid));
				muc_hosts[jid] = true;
			end
		end
	end
end

function module.unload()
	muc_hosts = nil;
end

module:add_event_hook("component-activated", function(component, config)
	if config.core.logging == true then
		module:log("debug", "component: %s", tostring(component));
		muc_hosts[component] = true;
	end
end);

module:hook("message/bare", logIfNeeded, 500);
module:hook("pre-message/bare", logIfNeeded, 500);
module:hook("iq/bare", logIfNeeded, 500);
module:hook("pre-iq/bare", logIfNeeded, 500);
module:hook("presence/full", logIfNeeded, 500);
module:hook("pre-presence/full", logIfNeeded, 500);
