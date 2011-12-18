package.preload['verse.plugins.presence'] = (function (...)
function verse.plugins.presence(stream)
	stream.last_presence = nil;

	stream:hook("presence-out", function (presence)
		if not presence.attr.to then
			stream.last_presence = presence; -- Cache non-directed presence
		end
	end, 1);

	function stream:resend_presence()
		if last_presence then
			stream:send(last_presence);
		end
	end

	function stream:set_status(opts)
		local p = verse.presence();
		if type(opts) == "table" then
			if opts.show then
				p:tag("show"):text(opts.show):up();
			end
			if opts.prio then
				p:tag("priority"):text(tostring(opts.prio)):up();
			end
			if opts.msg then
				p:tag("status"):text(opts.msg):up();
			end
		end
		-- TODO maybe use opts as prio if it's a int,
		-- or as show or status if it's a string?

		stream:send(p);
	end
end
 end)
package.preload['verse.plugins.groupchat'] = (function (...)
local events = require "events";

local room_mt = {};
room_mt.__index = room_mt;

local xmlns_delay = "urn:xmpp:delay";
local xmlns_muc = "http://jabber.org/protocol/muc";

function verse.plugins.groupchat(stream)
	stream:add_plugin("presence")
	stream.rooms = {};
	
	stream:hook("stanza", function (stanza)
		local room_jid = jid.bare(stanza.attr.from);
		if not room_jid then return end
		local room = stream.rooms[room_jid]
		if not room and stanza.attr.to and room_jid then
			room = stream.rooms[stanza.attr.to.." "..room_jid]
		end
		if room and room.opts.source and stanza.attr.to ~= room.opts.source then return end
		if room then
			local nick = select(3, jid.split(stanza.attr.from));
			local body = stanza:get_child_text("body");
			local delay = stanza:get_child("delay", xmlns_delay);
			local event = {
				room_jid = room_jid;
				room = room;
				sender = room.occupants[nick];
				nick = nick;
				body = body;
				stanza = stanza;
				delay = (delay and delay.attr.stamp);
			};
			local ret = room:event(stanza.name, event);
			return ret or (stanza.name == "message") or nil;
		end
	end, 500);
	
	function stream:join_room(jid, nick, opts)
		if not nick then
			return false, "no nickname supplied"
		end
		opts = opts or {};
		local room = setmetatable({
			stream = stream, jid = jid, nick = nick,
			subject = nil,
			occupants = {},
			opts = opts,
			events = events.new()
		}, room_mt);
		if opts.source then
			self.rooms[opts.source.." "..jid] = room;
		else
			self.rooms[jid] = room;
		end
		local occupants = room.occupants;
		room:hook("presence", function (presence)
			local nick = presence.nick or nick;
			if not occupants[nick] and presence.stanza.attr.type ~= "unavailable" then
				occupants[nick] = {
					nick = nick;
					jid = presence.stanza.attr.from;
					presence = presence.stanza;
				};
				local x = presence.stanza:get_child("x", xmlns_muc .. "#user");
				if x then
					local x_item = x:get_child("item");
					if x_item and x_item.attr then
						occupants[nick].real_jid    = x_item.attr.jid;
						occupants[nick].affiliation = x_item.attr.affiliation;
						occupants[nick].role        = x_item.attr.role;
					end
					--TODO Check for status 100?
				end
				if nick == room.nick then
					room.stream:event("groupchat/joined", room);
				else
					room:event("occupant-joined", occupants[nick]);
				end
			elseif occupants[nick] and presence.stanza.attr.type == "unavailable" then
				if nick == room.nick then
					room.stream:event("groupchat/left", room);
					if room.opts.source then
						self.rooms[room.opts.source.." "..jid] = nil;
					else
						self.rooms[jid] = nil;
					end
				else
					occupants[nick].presence = presence.stanza;
					room:event("occupant-left", occupants[nick]);
					occupants[nick] = nil;
				end
			end
		end);
		room:hook("message", function(event)
			local subject = event.stanza:get_child_text("subject");
			if not subject then return end
			subject = #subject > 0 and subject or nil;
			if subject ~= room.subject then
				local old_subject = room.subject;
				room.subject = subject;
				return room:event("subject-changed", { from = old_subject, to = subject, by = event.sender, event = event });
			end
		end, 2000);
		local join_st = verse.presence():tag("x",{xmlns = xmlns_muc}):reset();
		self:event("pre-groupchat/joining", join_st);
		room:send(join_st)
		self:event("groupchat/joining", room);
		return room;
	end

	stream:hook("presence-out", function(presence)
		if not presence.attr.to then
			for _, room in pairs(stream.rooms) do
				room:send(presence);
			end
			presence.attr.to = nil;
		end
	end);
end

function room_mt:send(stanza)
	if stanza.name == "message" and not stanza.attr.type then
		stanza.attr.type = "groupchat";
	end
	if stanza.name == "presence" then
		stanza.attr.to = self.jid .."/"..self.nick;
	end
	if stanza.attr.type == "groupchat" or not stanza.attr.to then
		stanza.attr.to = self.jid;
	end
	if self.opts.source then
		stanza.attr.from = self.opts.source
	end
	self.stream:send(stanza);
end

function room_mt:send_message(text)
	self:send(verse.message():tag("body"):text(text));
end

function room_mt:set_subject(text)
	self:send(verse.message():tag("subject"):text(text));
end

function room_mt:change_nick(new)
	self.nick = new;
	self:send(verse.presence());
end

function room_mt:leave(message)
	self.stream:event("groupchat/leaving", self);
	self:send(verse.presence({type="unavailable"}));
end

function room_mt:admin_set(nick, what, value, reason)
	self:send(verse.iq({type="set"})
		:query(xmlns_muc .. "#admin")
			:tag("item", {nick = nick, [what] = value})
				:tag("reason"):text(reason or ""));
end

function room_mt:set_role(nick, role, reason)
	self:admin_set(nick, "role", role, reason);
end

function room_mt:set_affiliation(nick, affiliation, reason)
	self:admin_set(nick, "affiliation", affiliation, reason);
end

function room_mt:kick(nick, reason)
	self:set_role(nick, "none", reason);
end

function room_mt:ban(nick, reason)
	self:set_affiliation(nick, "outcast", reason);
end

function room_mt:event(name, arg)
	self.stream:debug("Firing room event: %s", name);
	return self.events.fire_event(name, arg);
end

function room_mt:hook(name, callback, priority)
	return self.events.add_handler(name, callback, priority);
end
 end)
package.preload['verse.component'] = (function (...)
local verse = require "verse";
local stream = verse.stream_mt;

local jid_split = require "util.jid".split;
local lxp = require "lxp";
local st = require "util.stanza";
local sha1 = require "util.sha1".sha1;

-- Shortcuts to save having to load util.stanza
verse.message, verse.presence, verse.iq, verse.stanza, verse.reply, verse.error_reply =
	st.message, st.presence, st.iq, st.stanza, st.reply, st.error_reply;

local new_xmpp_stream = require "util.xmppstream".new;

local xmlns_stream = "http://etherx.jabber.org/streams";
local xmlns_component = "jabber:component:accept";

local stream_callbacks = {
	stream_ns = xmlns_stream,
	stream_tag = "stream",
	 default_ns = xmlns_component };
	
function stream_callbacks.streamopened(stream, attr)
	stream.stream_id = attr.id;
	if not stream:event("opened", attr) then
		stream.notopen = nil;
	end
	return true;
end

function stream_callbacks.streamclosed(stream)
	return stream:event("closed");
end

function stream_callbacks.handlestanza(stream, stanza)
	if stanza.attr.xmlns == xmlns_stream then
		return stream:event("stream-"..stanza.name, stanza);
	elseif stanza.attr.xmlns or stanza.name == "handshake" then
		return stream:event("stream/"..(stanza.attr.xmlns or xmlns_component), stanza);
	end

	return stream:event("stanza", stanza);
end

function stream:reset()
	if self.stream then
		self.stream:reset();
	else
		self.stream = new_xmpp_stream(self, stream_callbacks);
	end
	self.notopen = true;
	return true;
end

function stream:connect_component(jid, pass)
	self.jid, self.password = jid, pass;
	self.username, self.host, self.resource = jid_split(jid);
	
	function self.data(conn, data)
		local ok, err = self.stream:feed(data);
		if ok then return; end
		stream:debug("debug", "Received invalid XML (%s) %d bytes: %s", tostring(err), #data, data:sub(1, 300):gsub("[\r\n]+", " "));
		stream:close("xml-not-well-formed");
	end
	
	self:hook("incoming-raw", function (data) return self.data(self.conn, data); end);
	
	self.curr_id = 0;
	
	self.tracked_iqs = {};
	self:hook("stanza", function (stanza)
		local id, type = stanza.attr.id, stanza.attr.type;
		if id and stanza.name == "iq" and (type == "result" or type == "error") and self.tracked_iqs[id] then
			self.tracked_iqs[id](stanza);
			self.tracked_iqs[id] = nil;
			return true;
		end
	end);
	
	self:hook("stanza", function (stanza)
		if stanza.attr.xmlns == nil or stanza.attr.xmlns == "jabber:client" then
			if stanza.name == "iq" and (stanza.attr.type == "get" or stanza.attr.type == "set") then
				local xmlns = stanza.tags[1] and stanza.tags[1].attr.xmlns;
				if xmlns then
					ret = self:event("iq/"..xmlns, stanza);
					if not ret then
						ret = self:event("iq", stanza);
					end
				end
				if ret == nil then
					self:send(verse.error_reply(stanza, "cancel", "service-unavailable"));
					return true;
				end
			else
				ret = self:event(stanza.name, stanza);
			end
		end
		return ret;
	end, -1);

	self:hook("opened", function (attr)
		print(self.jid, self.stream_id, attr.id);
		local token = sha1(self.stream_id..pass, true);

		self:send(st.stanza("handshake", { xmlns = xmlns_component }):text(token));
		self:hook("stream/"..xmlns_component, function (stanza)
			if stanza.name == "handshake" then
				self:event("authentication-success");
			end
		end);
	end);

	local function stream_ready()
		self:event("ready");
	end
	self:hook("authentication-success", stream_ready, -1);

	-- Initialise connection
	self:connect(self.connect_host or self.host, self.connect_port or 5347);
	self:reopen();
end

function stream:reopen()
	self:reset();
	self:send(st.stanza("stream:stream", { to = self.host, ["xmlns:stream"]='http://etherx.jabber.org/streams',
		xmlns = xmlns_component, version = "1.0" }):top_tag());
end

function stream:close(reason)
	if not self.notopen then
		self:send("</stream:stream>");
	end
	local on_disconnect = self.conn.disconnect();
	self.conn:close();
	on_disconnect(conn, reason);
end

function stream:send_iq(iq, callback)
	local id = self:new_id();
	self.tracked_iqs[id] = callback;
	iq.attr.id = id;
	self:send(iq);
end

function stream:new_id()
	self.curr_id = self.curr_id + 1;
	return tostring(self.curr_id);
end
 end)

-- Use LuaRocks if available
pcall(require, "luarocks.require");

-- Load LuaSec if available
pcall(require, "ssl");

local server = require "net.server";
local events = require "util.events";
local logger = require "util.logger";

module("verse", package.seeall);
local verse = _M;
_M.server = server;

local stream = {};
stream.__index = stream;
stream_mt = stream;

verse.plugins = {};

local max_id = 0;

function verse.new(logger, base)
	local t = setmetatable(base or {}, stream);
	max_id = max_id + 1;
	t.id = tostring(max_id);
	t.logger = logger or verse.new_logger("stream"..t.id);
	t.events = events.new();
	t.plugins = {};
	t.verse = verse;
	return t;
end

verse.add_task = require "util.timer".add_task;

verse.logger = logger.init; -- COMPAT: Deprecated
verse.new_logger = logger.init;
verse.log = verse.logger("verse");

local function format(format, ...)
	local n, arg, maxn = 0, { ... }, select('#', ...);
	return (format:gsub("%%(.)", function (c) if n <= maxn then n = n + 1; return tostring(arg[n]); end end));
end

function verse.set_log_handler(log_handler, levels)
	levels = levels or { "debug", "info", "warn", "error" };
	logger.reset();
	local function _log_handler(name, level, message, ...)
		return log_handler(name, level, format(message, ...));
	end
	if log_handler then
		for i, level in ipairs(levels) do
			logger.add_level_sink(level, _log_handler);
		end
	end
end

function _default_log_handler(name, level, message)
	return io.stderr:write(name, "\t", level, "\t", message, "\n");
end
verse.set_log_handler(_default_log_handler, { "error" });

local function error_handler(err)
	verse.log("error", "Error: %s", err);
	verse.log("error", "Traceback: %s", debug.traceback());
end

function verse.set_error_handler(new_error_handler)
	error_handler = new_error_handler;
end

function verse.loop()
	return xpcall(server.loop, error_handler);
end

function verse.step()
	return xpcall(server.step, error_handler);
end

function verse.quit()
	return server.setquitting(true);
end

function stream:connect(connect_host, connect_port)
	connect_host = connect_host or "localhost";
	connect_port = tonumber(connect_port) or 5222;
	
	-- Create and initiate connection
	local conn = socket.tcp()
	conn:settimeout(0);
	local success, err = conn:connect(connect_host, connect_port);
	
	if not success and err ~= "timeout" then
		self:warn("connect() to %s:%d failed: %s", connect_host, connect_port, err);
		return self:event("disconnected", { reason = err }) or false, err;
	end

	local conn = server.wrapclient(conn, connect_host, connect_port, new_listener(self), "*a");
	if not conn then
		self:warn("connection initialisation failed: %s", err);
		return self:event("disconnected", { reason = err }) or false, err;
	end
	
	self.conn = conn;
	self.send = function (stream, data)
		self:event("outgoing", data);
		data = tostring(data);
		self:event("outgoing-raw", data);
		return conn:write(data);
	end;
	return true;
end

function stream:close()
	if not self.conn then 
		verse.log("error", "Attempt to close disconnected connection - possibly a bug");
		return;
	end
	local on_disconnect = self.conn.disconnect();
	self.conn:close();
	on_disconnect(conn, reason);
end

-- Logging functions
function stream:debug(...)
	return self.logger("debug", ...);
end

function stream:warn(...)
	return self.logger("warn", ...);
end

function stream:error(...)
	return self.logger("error", ...);
end

-- Event handling
function stream:event(name, ...)
	self:debug("Firing event: "..tostring(name));
	return self.events.fire_event(name, ...);
end

function stream:hook(name, ...)
	return self.events.add_handler(name, ...);
end

function stream:unhook(name, handler)
	return self.events.remove_handler(name, handler);
end

function verse.eventable(object)
        object.events = events.new();
        object.hook, object.unhook = stream.hook, stream.unhook;
        local fire_event = object.events.fire_event;
        function object:event(name, ...)
                return fire_event(name, ...);
        end
        return object;
end

function stream:add_plugin(name)
	if self.plugins[name] then return true; end
	if require("verse.plugins."..name) then
		local ok, err = verse.plugins[name](self);
		if ok ~= false then
			self:debug("Loaded %s plugin", name);
			self.plugins[name] = true;
		else
			self:warn("Failed to load %s plugin: %s", name, err);
		end
	end
	return self;
end

-- Listener factory
function new_listener(stream)
	local conn_listener = {};
	
	function conn_listener.onconnect(conn)
		stream.connected = true;
		stream:event("connected");
	end
	
	function conn_listener.onincoming(conn, data)
		stream:event("incoming-raw", data);
	end
	
	function conn_listener.ondisconnect(conn, err)
		stream.connected = false;
		stream:event("disconnected", { reason = err });
	end

	function conn_listener.ondrain(conn)
		stream:event("drained");
	end
	
	function conn_listener.onstatus(conn, new_status)
		stream:event("status", new_status);
	end
	
	return conn_listener;
end

return verse;

