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

local jid = require "util.jid";

local function irc2muc(channel, nick)
        channel = channel:gsub("^#", "")
        channel = channel:gsub("(%s:)$", "")
        return jid.join(channel, muc_server, nick)
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

local irc_listener = { default_port = 7000, default_mode = "*l" };

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
                                        session.send(":" .. muc_server .. " 451 " .. command .. " :You have not registered")
                                        return true;
                                end
                        end
                        if commands[command] then
                                local ret = commands[command](session, args);
                                if ret then
                                        session.send(ret.."\r\n");
                                end
                        else
                                session.send(":" .. muc_server .. " 421 " .. session.nick .. " " .. command .. " :Unknown command")
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
        if jids[session.full_jid] then jids[session.full_jid] = nil end
        if nicks[session.nick] then nicks[session.nick] = nil end
        if sessions[conn] then sessions[conn] = nil end
end

function commands.NICK(session, nick)
        if session.nick then
                session.send(":"..muc_server.." 484 * "..nick.." :I'm afraid I can't let you do that, "..nick);
                --TODO Loop throug all rooms and change nick, with help from Verse.
                return;
        end
        nick = nick:match("^[%w_:]+"); nick = nick:gsub(":", "");
        if nicks[nick] then
                session.send(":"..muc_server.." 433 * "..nick.." :The nickname "..nick.." is already in use");
                return;
        end
        local full_jid = jid.join(nick, component_jid, "ircd");
        jids[full_jid] = session;
        nicks[nick] = session;
        session.nick = nick;
        session.full_jid = full_jid;
        session.type = "c2s";
        session.send(":"..muc_server.." 001 "..session.nick.." :Welcome in the IRC to MUC XMPP Gateway, "..session.nick);
	session.send(":"..muc_server.." 002 "..session.nick.." :Your host is "..muc_server..", running Prosody "..prosody.version);
	session.send(":"..muc_server.." 004 "..session.nick.." :"..muc_server.." Prosody("..prosody.version..") i ov");
	session.send(":"..muc_server.." 375 "..session.nick.." :- "..muc_server.." Message of the day -");
	session.send(":"..muc_server.." 372 "..session.nick.." :-");
	session.send(":"..muc_server.." 372 "..session.nick.." :- Please be warned that this is only a partial irc implementation,");
	session.send(":"..muc_server.." 372 "..session.nick.." :- it's made to facilitate users transiting away from irc to XMPP.");
	session.send(":"..muc_server.." 372 "..session.nick.." :-");
	session.send(":"..muc_server.." 372 "..session.nick.." :- Prosody is _NOT_ an IRC Server and it never will.");
	session.send(":"..muc_server.." 372 "..session.nick.." :- We also would like to remind you that this plugin is provided as is,");
	session.send(":"..muc_server.." 372 "..session.nick.." :- it's still an Alpha and it's still a work in progress, use it at your sole");
	session.send(":"..muc_server.." 372 "..session.nick.." :- risk as there's a not so little chance something will break.");
	session.send(":"..session.nick.." MODE "..session.nick.." +i");
end

function commands.USER(session, params)
end

function commands.JOIN(session, channel)
        local room_jid = irc2muc(channel);
        channel = channel:gsub("(%s:)$", "")
        local room, err = c:join_room(room_jid, session.nick, { source = session.full_jid } );
        if not room then
                return ":"..session.host.." ERR :Could not join room: "..err
        end
        session.rooms[channel] = room;
        room.channel = channel;
        room.session = session;
        if room.subject then
        	session.send(":"..session.host.." 332 "..session.nick.." "..channel.." :"..room.subject);
        end
        commands.NAMES(session, channel)
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
        room:hook("subject-changed", function(changed) 
        	session.send((":%s TOPIC %s :%s"):format(changed.by, channel, changed.to or ""));
	end);
end

c:hook("groupchat/joined", function(room)
        local session = room.session or jids[room.opts.source];
        local channel = "#"..room.jid:match("^(.*)@");
        session.send((":%s!%s JOIN :%s"):format(session.nick, session.nick, channel));
        if room.topic then
                session.send((":%s 332 %s :%s"):format(muc_server, channel, room.topic));
        end
        commands.NAMES(session, channel)
        --FIXME Ones own mode get's lost
        --session.send((":%s MODE %s +%s %s"):format(session.host, room.channel, modemap[nick.role], nick.nick));
        room:hook("occupant-joined", function(nick)
                session.send((":%s!%s JOIN :%s"):format(nick.nick, nick.nick, channel));
                if nick.role and modemap[nick.role] then
                        session.send((":%s MODE %s +%s %s"):format(muc_server, channel, modemap[nick.role], nick.nick));
                end
        end);
        room:hook("occupant-left", function(nick)
                session.send((":%s!%s PART :%s"):format(nick.nick, nick.nick, channel));
        end);
end);

function commands.NAMES(session, channel)
        local nicks = { };
        channel = channel:gsub("^:", "")
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
        session.send(":"..muc_server.." 353 "..session.nick.." = "..channel.." :"..nicks);
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
        session.send(":"..muc_server..": PONG "..server);
end

function commands.TOPIC(session, message)
	if not message then return end
	local channel, topic = message:match("^(%S+) :(.*)$");
	if not channel then
		channel = message:match("^(%S+)");
	end
	if not channel then return end
	local room = session.rooms[channel];
	if topic then
		room:set_subject(topic)
		session.send((":%s TOPIC %s :%s"):format(muc_server, channel, room.subject or ""));
	else
		session.send((":%s TOPIC %s :%s"):format(muc_server, channel, room.subject or ""));
		-- first should be who set it, but verse doesn't provide that yet, so we'll
		-- just say it was the server
	end
end

function commands.WHO(session, channel)
	channel = channel:gsub("^:", "")
        if session.rooms[channel] then
                local room = session.rooms[channel]
                for nick in pairs(room.occupants) do
                        session.send(":"..muc_server.." 352 "..session.nick.." "..channel.." "..nick.." "..nick.." "..muc_server.." "..nick.." H :0 "..nick);
                end
                session.send(":"..muc_server.." 315 "..session.nick.." "..channel.. " :End of /WHO list");
        end
end

function commands.MODE(session, channel)
        session.send(":"..muc_server.." 324 "..session.nick.." "..channel.." +J"); 
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
end

local function desetup()
	require "net.connlisteners".deregister("irc");
end

require "net.connlisteners".register("irc", irc_listener);
require "net.connlisteners".start("irc");

module:hook("module-unloaded", desetup)
