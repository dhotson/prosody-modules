-- README
-- Squish verse into this dir, then squish them into one, which you move
-- and rename to mod_ircd.lua in your prosody modules/plugins dir.
--
-- IRC spec:
-- http://tools.ietf.org/html/rfc2812
local _module = module
module = _G.module
local module = _module
--
local component_jid, component_secret, muc_server =
      module.host, nil, module:get_option("conference_server");

package.loaded["util.sha1"] = require "util.encodings";
local verse = require "verse"
require "verse.component"
require "socket"
c = verse.new();--verse.logger())
c:add_plugin("groupchat");

local function verse2prosody(e)
	return c:event("stanza", e.stanza) or true;
end
module:hook("message/bare", verse2prosody);
module:hook("message/full", verse2prosody);
module:hook("presence/bare", verse2prosody);
module:hook("presence/full", verse2prosody);
c.type = "component";
c.send = core_post_stanza;

-- This plugin is actually a verse based component, but that mode is currently commented out

-- Add some hooks for debugging
--c:hook("opened", function () print("Stream opened!") end);
--c:hook("closed", function () print("Stream closed!") end);
--c:hook("stanza", function (stanza) print("Stanza:", stanza) end);

-- This one prints all received data
--c:hook("incoming-raw", print, 1000);
--c:hook("stanza", print, 1000);
--c:hook("outgoing-raw", print, 1000);

-- Print a message after authentication
--c:hook("authentication-success", function () print("Logged in!"); end);
--c:hook("authentication-failure", function (err) print("Failed to log in! Error: "..tostring(err.condition)); end);

-- Print a message and exit when disconnected
--c:hook("disconnected", function () print("Disconnected!"); os.exit(); end);

-- Now, actually start the connection:
--c.connect_host = "127.0.0.1"
--c:connect_component(component_jid, component_secret);

local jid = require "util.jid";

local function irc2muc(channel, nick)
	return jid.join(channel:gsub("^#", ""), muc_server, nick)
end
local function muc2irc(room)
	local channel, _, nick = jid.split(room);
	return "#"..channel, nick;
end
local rolemap = {
	moderator = "@",
	participant = "+",
}
local modemap = {
	moderator = "o",
	participant = "v",
}

local irc_listener = { default_port = 6667, default_mode = "*l" };

local sessions = {};
local jids = {};
local commands = {};

local nicks = {};

local st = require "util.stanza";

local conference_server = muc_server;

local function irc_close_session(session)
	session.conn:close();
end

function irc_listener.onincoming(conn, data)
	local session = sessions[conn];
	if not session then
		session = { conn = conn, host = component_jid, reset_stream = function () end,
			close = irc_close_session, log = logger.init("irc"..(conn.id or "1")),
			rooms = {},
			roster = {} };
		sessions[conn] = session;
		function session.data(data)
			local command, args = data:match("^%s*([^ ]+) *(.*)%s*$");
			if not command then
				return;
			end
			command = command:upper();
			if not session.nick then
				if not (command == "USER" or command == "NICK") then
					session.send(":" .. session.host .. " 451 " .. command .. " :You have not registered")
				end
			end
			if commands[command] then
				local ret = commands[command](session, args);
				if ret then
					session.send(ret.."\r\n");
				end
			else
				session.send(":" .. session.host .. " 421 " .. session.nick .. " " .. command .. " :Unknown command")
				module:log("debug", "Unknown command: %s", command);
			end
		end
		function session.send(data)
			return conn:write(data.."\r\n");
		end
	end
	if data then
		session.data(data);
	end
end

function irc_listener.ondisconnect(conn, error)
	local session = sessions[conn];
	for _, room in pairs(session.rooms) do
		room:leave("Disconnected");
	end
	jids[session.full_jid] = nil;
	nicks[session.nick] = nil;
	sessions[conn] = nil;
end

function commands.NICK(session, nick)
	if session.nick then
		session.send(":"..session.host.." 484 * "..nick.." :I'm afraid I can't let you do that, "..nick);
		--TODO Loop throug all rooms and change nick, with help from Verse.
		return;
	end
	nick = nick:match("^[%w_]+");
	if nicks[nick] then
		session.send(":"..session.host.." 433 * "..nick.." :The nickname "..nick.." is already in use");
		return;
	end
	local full_jid = jid.join(nick, component_jid, "ircd");
	jids[full_jid] = session;
	nicks[nick] = session;
	session.nick = nick;
	session.full_jid = full_jid;
	session.type = "c2s";
	session.send(":"..session.host.." 001 "..session.nick.." :Welcome to XMPP via the "..session.host.." gateway "..session.nick);
end

function commands.USER(session, params)
	-- FIXME
	-- Empty command for now
end

function commands.JOIN(session, channel)
	local room_jid = irc2muc(channel);
	print(session.full_jid);
	local room, err = c:join_room(room_jid, session.nick, { source = session.full_jid } );
	if not room then
		return ":"..session.host.." ERR :Could not join room: "..err
	end
	session.rooms[channel] = room;
	room.channel = channel;
	room.session = session;
	session.send(":"..session.nick.." JOIN :"..channel);
	session.send(":"..session.host.." 332 "..session.nick.." "..channel.." :Connection in progress...");
	room:hook("message", function(event)
		if not event.body then return end
		local nick, body = event.nick, event.body;
		if nick ~= session.nick then
			if body:sub(1,4) == "/me " then
				body = "\1ACTION ".. body:sub(5) .. "\1"
			end
			session.send(":"..nick.." PRIVMSG "..channel.." :"..body);
			--FIXME PM's probably won't work
		end
	end);
end

c:hook("groupchat/joined", function(room)
	local session = room.session or jids[room.opts.source];
	local channel = room.channel;
	session.send((":%s!%s JOIN %s :"):format(session.nick, session.nick, channel));
	if room.topic then
		session.send((":%s 332 %s :%s"):format(session.host, channel, room.topic));
	end
	commands.NAMES(session, channel)
	--FIXME Ones own mode get's lost
	--session.send((":%s MODE %s +%s %s"):format(session.host, room.channel, modemap[nick.role], nick.nick));
	room:hook("occupant-joined", function(nick)
		session.send((":%s!%s JOIN :%s"):format(nick.nick, nick.nick, channel));
		if nick.role and modemap[nick.role] then
			session.send((":%s MODE %s +%s %s"):format(session.host, room.channel, modemap[nick.role], nick.nick));
		end
	end);
	room:hook("occupant-left", function(nick)
		session.send((":%s!%s PART %s :"):format(nick.nick, nick.nick, channel));
	end);
end);

function commands.NAMES(session, channel)
	local nicks = { };
	local room = session.rooms[channel];
	if not room then return end
	-- TODO Break this out into commands.NAMES
	for nick, n in pairs(room.occupants) do
		if n.role and rolemap[n.role] then
			nick = rolemap[n.role] .. nick;
		end
		table.insert(nicks, nick);
	end
	nicks = table.concat(nicks, " ");
	--:molyb.irc.bnfh.org 353 derp = #grill-bit :derp hyamobi walt snuggles_ E-Rock kng grillbit gunnarbot Frink shedma zagabar zash Mrw00t Appiah J10 lectus peck EricJ soso mackt offer hyarion @pettter MMN-o 
	session.send((":%s 353 %s = %s :%s"):format(session.host, session.nick, channel, nicks));
	session.send((":%s 366 %s %s :End of /NAMES list."):format(session.host, session.nick, channel));
	session.send(":"..session.host.." 353 "..session.nick.." = "..channel.." :"..nicks);
end

function commands.PART(session, channel)
	local channel, part_message = channel:match("^([^:]+):?(.*)$");
	channel = channel:match("^([%S]*)");
	session.rooms[channel]:leave(part_message);
	session.send(":"..session.nick.." PART :"..channel);
end

function commands.PRIVMSG(session, message)
	local channel, message = message:match("^(%S+) :(.+)$");
	if message and #message > 0 and session.rooms[channel] then
		if message:sub(1,8) == "\1ACTION " then
			message = "/me ".. message:sub(9,-2)
		end
		module:log("debug", "%s sending PRIVMSG \"%s\" to %s", session.nick, message, channel);
		session.rooms[channel]:send_message(message);
	end
end

function commands.PING(session, server)
	session.send(":"..session.host..": PONG "..server);
end

function commands.WHO(session, channel)
	if session.rooms[channel] then
		local room = session.rooms[channel]
		for nick in pairs(room.occupants) do
			--n=MattJ 91.85.191.50 irc.freenode.net MattJ H :0 Matthew Wild
			session.send(":"..session.host.." 352 "..session.nick.." "..channel.." "..nick.." "..nick.." "..session.host.." "..nick.." H :0 "..nick);
		end
		session.send(":"..session.host.." 315 "..session.nick.." "..channel.. " :End of /WHO list");
	end
end

function commands.MODE(session, channel)
	session.send(":"..session.host.." 324 "..session.nick.." "..channel.." +J"); 
end

function commands.QUIT(session, message)
	session.send("ERROR :Closing Link: "..session.nick);
	for _, room in pairs(session.rooms) do
		room:leave(message);
	end
	jids[session.full_jid] = nil;
	nicks[session.nick] = nil;
	sessions[session.conn] = nil;
	session:close();
end

function commands.RAW(session, data)
	--c:send(data)
end

--c:hook("ready", function ()
	require "net.connlisteners".register("irc", irc_listener);
	require "net.connlisteners".start("irc");
--end);

--print("Starting loop...")
--verse.loop()

--[[ TODO

This is so close to working as a Prosody plugin you know ^^
Zash: :D
MattJ: That component function can go
Prosody fires events now
but verse fires "message" where Prosody fires "message/bare"
[20:59:50] 
Easy... don't connect_component
hook "message/*" and presence, and whatever
and call c:event("message", ...)
module:hook("message/bare", function (e) c:event("message", e.stanza) end)
as an example
That's so bad ^^
and override c:send() to core_post_stanza...

--]]

