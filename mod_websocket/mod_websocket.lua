-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- Copyright (C) 2012 Florian Zeitz
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

module:set_global();

local add_task = require "util.timer".add_task;
local new_xmpp_stream = require "util.xmppstream".new;
local nameprep = require "util.encodings".stringprep.nameprep;
local sessionmanager = require "core.sessionmanager";
local st = require "util.stanza";
local sm_new_session, sm_destroy_session = sessionmanager.new_session, sessionmanager.destroy_session;
local uuid_generate = require "util.uuid".generate;
local sha1 = require "util.hashes".sha1;
local base64 = require "util.encodings".base64.encode;
local band = require "bit".band;
local bxor = require "bit".bxor;
local tohex = require "bit".tohex;

local xpcall, tostring, type = xpcall, tostring, type;
local traceback = debug.traceback;

local xmlns_xmpp_streams = "urn:ietf:params:xml:ns:xmpp-streams";

local log = module._log;

local c2s_timeout = module:get_option_number("c2s_timeout");
local opt_keepalives = module:get_option_boolean("tcp_keepalives", false);

local sessions = module:shared("sessions");

local stream_callbacks = { default_ns = "jabber:client", handlestanza = core_process_stanza };
local listener = {};

-- Websocket helpers
local function parse_frame(frame)
	local result = {};
	local pos = 1;
	local length_bytes = 0;
	local counter = 0;
	local tmp_byte;

	tmp_byte = string.byte(frame, pos);
	result.FIN = band(tmp_byte, 0x80) > 0;
	result.RSV1 = band(tmp_byte, 0x40) > 0;
	result.RSV2 = band(tmp_byte, 0x20) > 0;
	result.RSV3 = band(tmp_byte, 0x10) > 0;
	result.opcode = band(tmp_byte, 0x0F) > 0;

	pos = pos + 1;
	tmp_byte = string.byte(frame, pos);
	result.MASK = band(tmp_byte, 0x80) > 0;
	result.length = band(tmp_byte, 0x7F);

	if result.length == 126 then
		length_bytes = 2;
		result.length = 0;
	elseif result.length == 127 then
		length_bytes = 8;
		result.length = 0;
	end

	for i = 1, length_bytes do
		pos = pos + 1;
		result.length = result.length * 255 + string.byte(frame, pos);
	end

	if result.MASK then
		result.key = {string.byte(frame, pos+1), string.byte(frame, pos+2),
				string.byte(frame, pos+3), string.byte(frame, pos+4)}

		pos = pos + 5;
		result.data = "";
		for i = pos, pos + result.length - 1 do
			result.data = result.data .. string.char(bxor(result.key[counter+1], string.byte(frame, i)));
			counter = (counter + 1) % 4;
		end
	else
		result.data = frame:sub(pos + 1, pos + result.length);
	end

	return result;
end

local function build_frame(desc)
	local length;
	local result = "";

	result = result .. string.char(0x80 * (desc.FIN and 1 or 0) + desc.opcode);

	length = #desc.data;
	if length <= 125 then -- 7-bit length
		result = result .. string.char(length);
	elseif length <= 0xFFFF then -- 2-byte length
		result = result .. string.char(126);
		result = result .. string.char(length/0x100) .. string.char(length%0x100);
	else -- 8-byte length
		result = result .. string.char(127);
		for i = 7, 0, -1 do
			result = result .. string.char(( length / (2^(8*i)) ) % 0x100);
		end
	end

	result = result .. desc.data;

	return result;
end

--- Stream events handlers
local stream_xmlns_attr = {xmlns='urn:ietf:params:xml:ns:xmpp-streams'};
local default_stream_attr = { ["xmlns:stream"] = "http://etherx.jabber.org/streams", xmlns = stream_callbacks.default_ns, version = "1.0", id = "" };

function stream_callbacks.streamopened(session, attr)
	local send = session.send;
	session.host = nameprep(attr.to);
	if not session.host then
		session:close{ condition = "improper-addressing",
			text = "A valid 'to' attribute is required on stream headers" };
		return;
	end
	session.version = tonumber(attr.version) or 0;
	session.streamid = uuid_generate();
	(session.log or session)("debug", "Client sent opening <stream:stream> to %s", session.host);

	if not hosts[session.host] then
		-- We don't serve this host...
		session:close{ condition = "host-unknown", text = "This server does not serve "..tostring(session.host)};
		return;
	end

	-- COMPAT: Current client implementations need this to be self-closing
	send("<?xml version='1.0'?>"..(tostring(st.stanza("stream:stream", {
		xmlns = 'jabber:client', ["xmlns:stream"] = 'http://etherx.jabber.org/streams';
		id = session.streamid, from = session.host, version = '1.0', ["xml:lang"] = 'en' }):top_tag()):gsub(">", "/>")));

	(session.log or log)("debug", "Sent reply <stream:stream> to client");
	session.notopen = nil;

	-- If session.secure is *false* (not nil) then it means we /were/ encrypting
	-- since we now have a new stream header, session is secured
	if session.secure == false then
		session.secure = true;
	end

	local features = st.stanza("stream:features");
	hosts[session.host].events.fire_event("stream-features", { origin = session, features = features });
	module:fire_event("stream-features", session, features);

	send(features);
end

function stream_callbacks.streamclosed(session)
	session.log("debug", "Received </stream:stream>");
	session:close();
end

function stream_callbacks.error(session, error, data)
	if error == "no-stream" then
		session.log("debug", "Invalid opening stream header");
		session:close("invalid-namespace");
	elseif error == "parse-error" then
		(session.log or log)("debug", "Client XML parse error: %s", tostring(data));
		session:close("not-well-formed");
	elseif error == "stream-error" then
		local condition, text = "undefined-condition";
		for child in data:children() do
			if child.attr.xmlns == xmlns_xmpp_streams then
				if child.name ~= "text" then
					condition = child.name;
				else
					text = child:get_text();
				end
				if condition ~= "undefined-condition" and text then
					break;
				end
			end
		end
		text = condition .. (text and (" ("..text..")") or "");
		session.log("info", "Session closed by remote with error: %s", text);
		session:close(nil, text);
	end
end

local function handleerr(err) log("error", "Traceback[c2s]: %s: %s", tostring(err), traceback()); end
function stream_callbacks.handlestanza(session, stanza)
	stanza = session.filter("stanzas/in", stanza);
	if stanza then
		return xpcall(function () return core_process_stanza(session, stanza) end, handleerr);
	end
end

--- Session methods
local function session_close(session, reason)
	local log = session.log or log;
	if session.conn then
		if session.notopen then
			session.send("<?xml version='1.0'?>");
			session.send(st.stanza("stream:stream", default_stream_attr):top_tag());
		end
		if reason then
			if type(reason) == "string" then -- assume stream error
				log("info", "Disconnecting client, <stream:error> is: %s", reason);
				session.send(st.stanza("stream:error"):tag(reason, {xmlns = 'urn:ietf:params:xml:ns:xmpp-streams' }));
			elseif type(reason) == "table" then
				if reason.condition then
					local stanza = st.stanza("stream:error"):tag(reason.condition, stream_xmlns_attr):up();
					if reason.text then
						stanza:tag("text", stream_xmlns_attr):text(reason.text):up();
					end
					if reason.extra then
						stanza:add_child(reason.extra);
					end
					log("info", "Disconnecting client, <stream:error> is: %s", tostring(stanza));
					session.send(stanza);
				elseif reason.name then -- a stanza
					log("info", "Disconnecting client, <stream:error> is: %s", tostring(reason));
					session.send(reason);
				end
			end
		end
		session.send("</stream:stream>");
		session.conn:close();
		listener.ondisconnect(session.conn, (reason and (reason.text or reason.condition)) or reason or "session closed");
	end
end

--- Port listener
function listener.onconnect(conn)
	local session = sm_new_session(conn);
	sessions[conn] = session;

	session.log("info", "Client connected");

	-- Client is using legacy SSL (otherwise mod_tls sets this flag)
	if conn:ssl() then
		session.secure = true;
	end

	if opt_keepalives then
		conn:setoption("keepalive", opt_keepalives);
	end

	session.close = session_close;

	local stream = new_xmpp_stream(session, stream_callbacks);
	session.stream = stream;
	session.notopen = true;

	function session.reset_stream()
		session.notopen = true;
		session.stream:reset();
	end

	local filter = session.filter;
	function session.data(data)
		data = parse_frame(data).data;
		module:log("debug", "Websocket received: %s %i", data, #data)
		-- COMPAT: Current client implementations send a self-closing <stream:stream>
		data = data:gsub("/>$", ">");

		data = filter("bytes/in", data);
		if data then
			local ok, err = stream:feed(data);
			if ok then return; end
			log("debug", "Received invalid XML (%s) %d bytes: %s", tostring(err), #data, data:sub(1, 300):gsub("[\r\n]+", " "):gsub("[%z\1-\31]", "_"));
			session:close("not-well-formed");
		end
	end

	function session.send(s)
		conn:write(build_frame({ FIN = true, opcode = 0x01, data = tostring(s)}));
	end

	if c2s_timeout then
		add_task(c2s_timeout, function ()
			if session.type == "c2s_unauthed" then
				session:close("connection-timeout");
			end
		end);
	end

	session.dispatch_stanza = stream_callbacks.handlestanza;
end

function listener.onincoming(conn, data)
	local session = sessions[conn];
	if session then
		session.data(data);
	else
		listener.onconnect(conn, data);
		session = sessions[conn];
		session.data(data);
	end
end

function listener.ondisconnect(conn, err)
	local session = sessions[conn];
	if session then
		(session.log or log)("info", "Client disconnected: %s", err);
		sm_destroy_session(session, err);
		sessions[conn]  = nil;
		session = nil;
	end
end

function listener.associate_session(conn, session)
	sessions[conn] = session;
end

function handle_request(event, path)
	local request, response = event.request, event.response;

	-- Add sanity checks

	response.conn:setlistener(listener);
	response.status = "101 Switching Protocols";
	response.headers.Upgrade = "websocket";
	response.headers.Connection = "Upgrade";
	response.headers.Sec_WebSocket_Accept = base64(sha1(request.headers.sec_websocket_key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"));
	response.headers.Sec_WebSocket_Protocol = "xmpp";

	return "";
end

function module.add_host(module)
	module:depends("http");
	module:provides("http", {
		name = "xmpp-websocket";
		route = {
			["GET /*"] = handle_request;
		};
	});
end
