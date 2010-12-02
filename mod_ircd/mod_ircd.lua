local irc_listener = { default_port = 6667, default_mode = "*l" };

local sessions = {};
local commands = {};

local nicks = {};

local st = require "util.stanza";

local conference_server = module:get_option("conference_server") or "conference.jabber.org";

local function irc_close_session(session)
	session.conn:close();
end

function irc_listener.onincoming(conn, data)
	local session = sessions[conn];
	if not session then
		session = { conn = conn, host = module.host, reset_stream = function () end,
			close = irc_close_session, log = logger.init("irc"..(conn.id or "1")),
			roster = {} };
		sessions[conn] = session;
		function session.data(data)
			module:log("debug", "Received: %s", data);
			local command, args = data:match("^%s*([^ ]+) *(.*)%s*$");
			if not command then
				module:log("warn", "Invalid command: %s", data);
				return;
			end
			command = command:upper();
			module:log("debug", "Received command: %s", command);
			if commands[command] then
				local ret = commands[command](session, args);
				if ret then
					session.send(ret.."\r\n");
				end
			end
		end
		function session.send(data)
			module:log("debug", "sending: %s", data);
			return conn:write(data.."\r\n");
		end
	end
	if data then
		session.data(data);
	end
end

function irc_listener.ondisconnect(conn, error)
	module:log("debug", "Client disconnected");
	sessions[conn] = nil;
end

function commands.NICK(session, nick)
	nick = nick:match("^[%w_]+");
	if nicks[nick] then
		session.send(":"..session.host.." 433 * "..nick.." :The nickname "..nick.." is already in use");
		return;
	end
	nicks[nick] = session;
	session.nick = nick;
	session.full_jid = nick.."@"..module.host.."/ircd";
	session.type = "c2s";
	module:log("debug", "Client bound to %s", session.full_jid);
	session.send(":"..session.host.." 001 "..session.nick.." :Welcome to XMPP via the "..session.host.." gateway "..session.nick);
end

local joined_mucs = {};
function commands.JOIN(session, channel)
	if not joined_mucs[channel] then
		joined_mucs[channel] = { occupants = {}, sessions = {} };
	end
	joined_mucs[channel].sessions[session] = true;
	local join_stanza = st.presence({ from = session.full_jid, to = channel:gsub("^#", "").."@"..conference_server.."/"..session.nick });
	core_process_stanza(session, join_stanza);
	session.send(":"..session.nick.." JOIN :"..channel);
	session.send(":"..session.host.." 332 "..session.nick.." "..channel.." :Connection in progress...");
        local nicks = session.nick;
        for nick in pairs(joined_mucs[channel].occupants) do
            nicks = nicks.." "..nick;
        end
        session.send(":"..session.host.." 353 "..session.nick.." = "..channel.." :"..nicks);
	session.send(":"..session.host.." 366 "..session.nick.." "..channel.." :End of /NAMES list.");
end

function commands.PART(session, channel)
	local channel, part_message = channel:match("^([^:]+):?(.*)$");
	channel = channel:match("^([%S]*)");
	core_process_stanza(session, st.presence{ type = "unavailable", from = session.full_jid,
		to = channel:gsub("^#", "").."@"..conference_server.."/"..session.nick }:tag("status"):text(part_message));
	session.send(":"..session.nick.." PART :"..channel);
end

function commands.PRIVMSG(session, message)
	local who, message = message:match("^(%S+) :(.+)$");
	if joined_mucs[who] then
		core_process_stanza(session, st.message{to=who:gsub("^#", "").."@"..conference_server, type="groupchat"}:tag("body"):text(message));
	end
end

function commands.PING(session, server)
	session.send(":"..session.host..": PONG "..server);
end

function commands.WHO(session, channel)
	if joined_mucs[channel] then
		for nick in pairs(joined_mucs[channel].occupants) do
			--n=MattJ 91.85.191.50 irc.freenode.net MattJ H :0 Matthew Wild
			session.send(":"..session.host.." 352 "..session.nick.." "..channel.." "..nick.." "..nick.." "..session.host.." "..nick.." H :0 "..nick);
		end
		session.send(":"..session.host.." 315 "..session.nick.." "..channel.. " :End of /WHO list");
	end
end

function commands.MODE(session, channel)
	session.send(":"..session.host.." 324 "..session.nick.." "..channel.." +J"); 
end

--- Component (handle stanzas from the server for IRC clients)
function irc_component(origin, stanza)
	local from, from_bare = stanza.attr.from, jid.bare(stanza.attr.from);
	local from_node = "#"..jid.split(stanza.attr.from);
	
	if joined_mucs[from_node] and from_bare == from then
		-- From room itself
		local joined_muc = joined_mucs[from_node];
		if stanza.name == "message" then
			local subject = stanza:get_child("subject");
			subject = subject and (subject:get_text() or "");
			if subject then
				for session in pairs(joined_muc.sessions) do
					session.send(":"..session.host.." 332 "..session.nick.." "..from_node.." :"..subject);
				end
			end
		end
	elseif joined_mucs[from_node] then
		-- From room occupant
		local joined_muc = joined_mucs[from_node];
		local nick = select(3, jid.split(from)):gsub(" ", "_");
		if stanza.name == "presence" then
			local what;
			if not stanza.attr.type then
				if joined_muc.occupants[nick] then
					return;
				end
				joined_muc.occupants[nick] = true;
				what = "JOIN";
			else
				joined_muc.occupants[nick] = nil;
				what = "PART";
			end
			for session in pairs(joined_muc.sessions) do
				if nick ~= session.nick then
					session.send(":"..nick.."!"..nick.." "..what.." :"..from_node);
				end
			end
		elseif stanza.name == "message" then
			local body = stanza:get_child("body");
			body = body and body:get_text() or "";
			local hasdelay = stanza:get_child("delay", "urn:xmpp:delay");
			if body ~= "" and nick then
				local to_nick = jid.split(stanza.attr.to);
				local session = nicks[to_nick];
				if nick ~= session.nick or hasdelay then
				    session.send(":"..nick.." PRIVMSG "..from_node.." :"..body);
				end
			end
			if not nick then
				module:log("error", "Invalid nick from JID: %s", from);
			end
		end
	end
end

local function stanza_handler(event)
	irc_component(event.origin, event.stanza);
	return true;
end
module:hook("iq/bare", stanza_handler, -1);
module:hook("message/bare", stanza_handler, -1);
module:hook("presence/bare", stanza_handler, -1);
module:hook("iq/full", stanza_handler, -1);
module:hook("message/full", stanza_handler, -1);
module:hook("presence/full", stanza_handler, -1);
module:hook("iq/host", stanza_handler, -1);
module:hook("message/host", stanza_handler, -1);
module:hook("presence/host", stanza_handler, -1);
require "core.componentmanager".register_component(module.host, function() end); -- COMPAT Prosody 0.7

prosody.events.add_handler("server-stopping", function (shutdown)
	module:log("debug", "Closing IRC connections prior to shutdown");
	for channel, joined_muc in pairs(joined_mucs) do
		for session in pairs(joined_muc.sessions) do
			core_process_stanza(session,
				st.presence{ type = "unavailable", from = session.full_jid,
					to = channel:gsub("^#", "").."@"..conference_server.."/"..session.nick }
					:tag("status")
						:text("Connection closed: Server is shutting down"..(shutdown.reason and (": "..shutdown.reason) or "")));
			session:close();
		end
	end
end);

require "net.connlisteners".register("irc", irc_listener);
require "net.connlisteners".start("irc", { port = module:get_option("port") });
