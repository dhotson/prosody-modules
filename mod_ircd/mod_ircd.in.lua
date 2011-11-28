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
local component_jid, component_secret, muc_server, port_number =
      module.host, nil, module:get_option_string("conference_server"), module:get_option_number("listener_port", 7000);

if not muc_server then
	module:log ("error", "You need to set the MUC server! halting.")
	return false;
end

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
local nodeprep = require "util.encodings".stringprep.nodeprep;

local function utf8_clean (s)
	local push, join = table.insert, table.concat;
	local r, i = {}, 1;
	if not(s and #s > 0) then
		return ""
	end
	while true do
		local c = s:sub(i,i)
		local b = c:byte();
		local w = (
			(b >= 9   and b <= 10  and 0) or
			(b >= 32  and b <= 126 and 0) or
			(b >= 192 and b <= 223 and 1) or
			(b >= 224 and b <= 239 and 2) or
			(b >= 240 and b <= 247 and 3) or
			(b >= 248 and b <= 251 and 4) or
			(b >= 251 and b <= 252 and 5) or nil
		)
		if not w then
			push(r, "?")
		else
			local n = i + w;
			if w == 0 then
				push(r, c);
			elseif n > #s then
				push(r, ("?"):format(b));
			else
				local e = s:sub(i+1,n);
				if e:match('^[\128-\191]*$') then
					push(r, c);
					push(r, e);
					i = n;
				else
					push(r, ("?"):format(b));
				end
			end
		end
		i = i + 1;
		if i > #s then
			break
		end
	end
	return join(r);
end

local function parse_line(line)
	local ret = {};
	if line:sub(1,1) == ":" then
		ret.from, line = line:match("^:(%w+)%s+(.*)$");
	end
	for part in line:gmatch("%S+") do
		if part:sub(1,1) == ":" then
			ret[#ret+1] = line:match(":(.*)$");
			break
		end
		ret[#ret+1]=part;
	end
	return ret;
end

local function build_line(parts)
	if #parts > 1 then
		parts[#parts] = ":" ..  parts[#parts];
	end
	return (parts.from and ":"..parts.from.." " or "")..table.concat(parts, " ");
end

local function irc2muc(channel, nick)
	local room = channel and nodeprep(channel:match("^#(%w+)")) or nil;
	return jid.join(room, muc_server, nick)
end
local function muc2irc(room)
	local channel, _, nick = jid.split(room);
	return "#"..channel, nick;
end
local role_map = {
        moderator = "@",
        participant = "",
        visitor = "",
        none = ""
}
local aff_map = {
	owner = "~",
	administrator = "&",
	member = "+",
	none = ""
}
local role_modemap = {
        moderator = "o",
        participant = "",
        visitor = "",
        none = ""
}
local aff_modemap = {
	owner = "q",
	administrator = "a",
	member = "v",
	none = ""
}

local irc_listener = { default_port = port_number, default_mode = "*l" };

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
			local parts = parse_line(data);
			module:log("debug", require"util.serialization".serialize(parts));
			local command = table.remove(parts, 1);
			if not command then
				return;
			end
			command = command:upper();
			if not session.nick then
				if not (command == "USER" or command == "NICK") then
					module:log("debug", "Client tried to send command %s before registering", command);
					return session.send{from=muc_server, "451", command, "You have not registered"}
				end
			end
			if commands[command] then
				local ret = commands[command](session, parts);
				if ret then
					return session.send(ret);
				end
			else
				session.send{from=muc_server, "421", session.nick, command, "Unknown command"};
				return module:log("debug", "Unknown command: %s", command);
			end
		end
		function session.send(data)
			if type(data) == "string" then
				return conn:write(data.."\r\n");
			elseif type(data) == "table" then
				local line = build_line(data);
				module:log("debug", line);
				conn:write(line.."\r\n");
			end
		end
	end
	if data then
		session.data(data);
	end
end

function irc_listener.ondisconnect(conn, error)
	local session = sessions[conn];
	if session then
		for _, room in pairs(session.rooms) do
			room:leave("Disconnected");
		end
		if session.nick then
			nicks[session.nick] = nil;
		end
		if session.full_jid then
			jids[session.full_jid] = nil;
		end
	end
	sessions[conn] = nil;
end

function commands.NICK(session, args)
	if session.nick then
		session.send{from = muc_server, "484", "*", nick, "I'm afraid I can't let you do that"};
		--TODO Loop throug all rooms and change nick, with help from Verse.
		return;
	end
	local nick = args[1];
	nick = nick:gsub("[^%w_]","");
	if nicks[nick] then
		session.send{from=muc_server, "433", nick, "The nickname "..nick.." is already in use"};
		return;
	end
	local full_jid = jid.join(nick, component_jid, "ircd");
	jids[full_jid] = session;
	jids[full_jid]["ar_last"] = {};
	nicks[nick] = session;
	session.nick = nick;
	session.full_jid = full_jid;
	session.type = "c2s";
	
	session.send{from = muc_server, "001", nick, "Welcome in the IRC to MUC XMPP Gateway, "..nick};
	session.send{from = muc_server, "002", nick, "Your host is "..muc_server.." running Prosody "..prosody.version};
	session.send{from = muc_server, "003", nick, "This server was created the "..os.date(nil, prosody.start_time)}
	session.send{from = muc_server, "004", nick, table.concat({muc_server, "mod_ircd(alpha-0.8)", "i", "aoqv"}, " ")};
	session.send{from = muc_server, "375", nick, "- "..muc_server.." Message of the day -"};
	session.send{from = muc_server, "372", nick, "-"};
	session.send{from = muc_server, "372", nick, "- Please be warned that this is only a partial irc implementation,"};
	session.send{from = muc_server, "372", nick, "- it's made to facilitate users transiting away from irc to XMPP."};
	session.send{from = muc_server, "372", nick, "-"};
	session.send{from = muc_server, "372", nick, "- Prosody is _NOT_ an IRC Server and it never will."};
	session.send{from = muc_server, "372", nick, "- We also would like to remind you that this plugin is provided as is,"};
	session.send{from = muc_server, "372", nick, "- it's still an Alpha and it's still a work in progress, use it at your sole"};
	session.send{from = muc_server, "372", nick, "- risk as there's a not so little chance something will break."};
	
	session.send{from = nick, "MODE", nick, "+i"}; -- why -> Invisible mode setting, 
						       --        enforce by default on most servers (since the source host doesn't show it's sensible to have it "set")
end

function commands.USER(session, params)
	-- FIXME
	-- Empty command for now
end

local function mode_map(am, rm, nicks)
	local rnick;
	local c_modes;
	c_modes = aff_modemap[am]..role_modemap[rm]
	rnick = string.rep(nicks.." ", c_modes:len())
	if c_modes == "" then return nil, nil end
	return c_modes, rnick
end

function commands.JOIN(session, args)
	local channel = args[1];
	if not channel then return end
	local room_jid = irc2muc(channel);
	print(session.full_jid);
	if not jids[session.full_jid].ar_last[room_jid] then jids[session.full_jid].ar_last[room_jid] = {}; end
	local room, err = c:join_room(room_jid, session.nick, { source = session.full_jid } );
	if not room then
		return ":"..muc_server.." ERR :Could not join room: "..err
	end
	session.rooms[channel] = room;
	room.channel = channel;
	room.session = session;
	session.send{from=session.nick, "JOIN", channel};
	if room.subject then
	       	session.send{from=muc_server, 332, session.nick, channel ,room.subject};
        end
	commands.NAMES(session, channel);
	
	room:hook("subject-changed", function(changed) 
	       	session.send((":%s TOPIC %s :%s"):format(changed.by.nick, channel, changed.to or ""));
	end);
	
	room:hook("message", function(event)
		if not event.body then return end
		local nick, body = event.nick, event.body;
		if nick ~= session.nick then
			if body:sub(1,4) == "/me " then
				body = "\1ACTION ".. body:sub(5) .. "\1"
			end
			local type = event.stanza.attr.type;
			session.send{from=nick, "PRIVMSG", type == "groupchat" and channel or nick, body};
			--FIXME PM's probably won't work
		end
	end);
	
	room:hook("presence", function(ar)
		local c_modes;
		local rnick;
		if ar.nick and not jids[session.full_jid].ar_last[ar.room_jid][ar.nick] then jids[session.full_jid].ar_last[ar.room_jid][ar.nick] = {} end
		local x_ar = ar.stanza:get_child("x", "http://jabber.org/protocol/muc#user")
		if x_ar then
		local xar_item = x_ar:get_child("item")
			if xar_item and xar_item.attr and ar.stanza.attr.type ~= "unavailable" then
		                if xar_item.attr.affiliation and xar_item.attr.role then
					if not jids[session.full_jid].ar_last[ar.room_jid][ar.nick]["affiliation"] and
					   not jids[session.full_jid].ar_last[ar.room_jid][ar.nick]["role"] then
						jids[session.full_jid].ar_last[ar.room_jid][ar.nick]["affiliation"] = xar_item.attr.affiliation
						jids[session.full_jid].ar_last[ar.room_jid][ar.nick]["role"] = xar_item.attr.role
						c_modes, rnick = mode_map(xar_item.attr.affiliation, xar_item.attr.role, ar.nick);
						if c_modes and rnick then session.send((":%s MODE %s +%s"):format(muc_server, channel, c_modes.." "..rnick)); end
					else
						c_modes, rnick = mode_map(jids[session.full_jid].ar_last[ar.room_jid][ar.nick]["affiliation"], jids[session.full_jid].ar_last[ar.room_jid][ar.nick]["role"], ar.nick);
						if c_modes and rnick then session.send((":%s MODE %s -%s"):format(muc_server, channel, c_modes.." "..rnick)); end
						jids[session.full_jid].ar_last[ar.room_jid][ar.nick]["affiliation"] = xar_item.attr.affiliation
						jids[session.full_jid].ar_last[ar.room_jid][ar.nick]["role"] = xar_item.attr.role
						c_modes, rnick = mode_map(xar_item.attr.affiliation, xar_item.attr.role, ar.nick);
						if c_modes and rnick then session.send((":%s MODE %s +%s"):format(muc_server, channel, c_modes.." "..rnick)); end
					end
				end
			end
		 end
	end, -1);
end

c:hook("groupchat/joined", function(room)
	local session = room.session or jids[room.opts.source];
        local channel = "#"..room.jid:match("^(.*)@");
	session.send{from=session.nick.."!"..session.nick, "JOIN", channel};
	if room.topic then
		session.send{from=muc_server, 332, room.topic};
	end
	commands.NAMES(session, channel)
	room:hook("occupant-joined", function(nick)
		session.send{from=nick.nick.."!"..nick.nick, "JOIN", channel};
	end);
	room:hook("occupant-left", function(nick)
		jids[session.full_jid].ar_last[nick.jid:match("^(.*)/")][nick.nick] = nil; -- ugly
		session.send{from=nick.nick.."!"..nick.nick, "PART", channel};
	end);
end);

function commands.NAMES(session, channel)
	local nicks = { };
	local room = session.rooms[channel];
	local symbols_map = {
		owner = "~",
		administrator = "&",
		moderator = "@",
		member = "+"
	}
		
	if not room then return end
	-- TODO Break this out into commands.NAMES
	for nick, n in pairs(room.occupants) do
                if n.affiliation == "owner" and n.role == "moderator" then
			nick = symbols_map[n.affiliation]..nick;
                elseif n.affiliation == "administrator" and n.role == "moderator" then
			nick = symbols_map[n.affiliation]..nick;
		elseif n.affiliation == "member" and n.role == "moderator" then
			nick = symbols_map[n.role]..nick;
		elseif n.affiliation == "member" and n.role == "partecipant" then
			nick = symbols_map[n.affiliation]..nick;
		elseif n.affiliation == "none" and n.role == "moderator" then
			nick = symbols_map[n.role]..nick;
		end
		table.insert(nicks, nick);
	end
	nicks = table.concat(nicks, " ");
	session.send((":%s 353 %s = %s :%s"):format(muc_server, session.nick, channel, nicks));
	session.send((":%s 366 %s %s :End of /NAMES list."):format(muc_server, session.nick, channel));
	session.send(":"..muc_server.." 353 "..session.nick.." = "..channel.." :"..nicks);
end

function commands.PART(session, args)
	local channel, part_message = unpack(args);
	local room = channel and nodeprep(channel:match("^#(%w+)")) or nil;
	if not room then return end
	channel = channel:match("^([%S]*)");
	session.rooms[channel]:leave(part_message);
	jids[session.full_jid].ar_last[room.."@"..muc_server] = nil;
	session.send(":"..session.nick.." PART :"..channel);
end

function commands.PRIVMSG(session, args)
	local channel, message = unpack(args);
	if message and #message > 0 then
		if message:sub(1,8) == "\1ACTION " then
			message = "/me ".. message:sub(9,-2)
		end
		message = utf8_clean(message);
		if channel:sub(1,1) == "#" then
			if session.rooms[channel] then
				module:log("debug", "%s sending PRIVMSG \"%s\" to %s", session.nick, message, channel);
				session.rooms[channel]:send_message(message);
			end
		else -- private message
			local nick = channel;
			module:log("debug", "PM to %s", nick);
			for channel, room in pairs(session.rooms) do
				module:log("debug", "looking for %s in %s", nick, channel);
				if room.occupants[nick] then
					module:log("debug", "found %s in %s", nick, channel);
					local who = room.occupants[nick];
					-- FIXME PMs in verse
					--room:send_private_message(nick, message);
					local pm = st.message({type="chat",to=who.jid}, message);
					module:log("debug", "sending PM to %s: %s", nick, tostring(pm));
					room:send(pm)
					break
				end
			end
		end
	end
end

function commands.PING(session, args)
	session.send{from=muc_server, "PONG", args[1]};
end

function commands.TOPIC(session, message)
	if not message then return end
	local channel, topic = message[1], message[2];
	channel = utf8_clean(channel);
	topic = utf8_clean(topic);
	if not channel then return end
	local room = session.rooms[channel];

	if topic then
		room:set_subject(topic)
		session.send((":%s TOPIC %s :%s"):format(room.nick, room.channel, room.subject or ""));
	end
end

function commands.WHO(session, args)
	local channel = args[1];
	if session.rooms[channel] then
		local room = session.rooms[channel]
		for nick in pairs(room.occupants) do
			--n=MattJ 91.85.191.50 irc.freenode.net MattJ H :0 Matthew Wild
			session.send{from=muc_server, 352, session.nick, channel, nick, nick, muc_server, nick, "H", "0 "..nick}
		end
		session.send{from=muc_server, 315, session.nick, channel, "End of /WHO list"};
	end
end

function commands.MODE(session, args) -- FIXME
	-- emptied for the time being, until something sane which works is available.
end

function commands.QUIT(session, args)
	session.send{"ERROR", "Closing Link: "..session.nick};
	for _, room in pairs(session.rooms) do
		room:leave(args[1]);
	end
	jids[session.full_jid] = nil;
	nicks[session.nick] = nil;
	sessions[session.conn] = nil;
	session:close();
end

function commands.RAW(session, data)
	--c:send(data)
end

local function desetup()
	require "net.connlisteners".deregister("irc");
end

--c:hook("ready", function ()
	require "net.connlisteners".register("irc", irc_listener);
	require "net.connlisteners".start("irc");
--end);

module:hook("module-unloaded", desetup)


--print("Starting loop...")
--verse.loop()
