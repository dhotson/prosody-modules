module.host = "*" -- Global module

local logger = require "util.logger";
local log = logger.init("mod_websocket");
local httpserver = require "net.httpserver";
local lxp = require "lxp";
local init_xmlhandlers = require "core.xmlhandlers";
local st = require "util.stanza";
local sm = require "core.sessionmanager";

local sessions = {};
local default_headers = { };


local stream_callbacks = { default_ns = "jabber:client",
		streamopened = sm.streamopened,
		streamclosed = sm.streamclosed,
		handlestanza = core_process_stanza };
function stream_callbacks.error(session, error, data)
	if error == "no-stream" then
		session.log("debug", "Invalid opening stream header");
		session:close("invalid-namespace");
	elseif session.close then
		(session.log or log)("debug", "Client XML parse error: %s", tostring(error));
		session:close("xml-not-well-formed");
	end
end


local function session_reset_stream(session)
	local parser = lxp.new(init_xmlhandlers(session, stream_callbacks), "\1");
	session.parser = parser;

	session.notopen = true;

	function session.data(conn, data)
		data, _ = data:gsub("[%z\255]", "")
		log("debug", "Parsing: %s", data)

		local ok, err = parser:parse(data)
		if not ok then
			log("debug", "Received invalid XML (%s) %d bytes: %s", tostring(err), #data,
				data:sub(1, 300):gsub("[\r\n]+", " "):gsub("[%z\1-\31]", "_"));
			session:close("xml-not-well-formed");
		end
	end
end

local stream_xmlns_attr = {xmlns='urn:ietf:params:xml:ns:xmpp-streams'};
local default_stream_attr = { ["xmlns:stream"] = "http://etherx.jabber.org/streams", xmlns = stream_callbacks.default_ns, version = "1.0", id = "" };
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
		websocket_listener.ondisconnect(session.conn, (reason and (reason.text or reason.condition)) or reason or "session closed");
	end
end


local websocket_listener = { default_mode = "*a" };
function websocket_listener.onincoming(conn, data)
	local session = sessions[conn];
	if not session then
		session = { type = "c2s_unauthed",
			conn = conn,
			reset_stream = session_reset_stream,
			close = session_close,
			dispatch_stanza = stream_callbacks.handlestanza,
			log = logger.init("websocket"),
			secure = conn.ssl };

		function session.send(s)
			conn:write("\00" .. tostring(s) .. "\255");
		end

		sessions[conn] = session;
	end

	session_reset_stream(session);

	if data then
		session.data(conn, data);
	end
end

function websocket_listener.ondisconnect(conn, err)
	local session = sessions[conn];
	if session then
		(session.log or log)("info", "Client disconnected: %s", err);
		sm.destroy_session(session, err);
		sessions[conn] = nil;
		session = nil;
	end
end


function handle_request(method, body, request)
	if request.method ~= "GET" or request.headers["upgrade"] ~= "WebSocket" or request.headers["connection"] ~= "Upgrade" then
		if request.method == "OPTIONS" then
			return { headers = default_headers, body = "" };
		else
			return "<html><body>You really don't look like a Websocket client to me... what do you want?</body></html>";
		end
	end

	local subprotocol = request.headers["Websocket-Protocol"];
	if subprotocol ~= nil and subprotocol ~= "XMPP" then
		return "<html><body>You really don't look like an XMPP Websocket client to me... what do you want?</body></html>";
	end

	if not method then
		log("debug", "Request %s suffered error %s", tostring(request.id), body);
		return;
	end

	request.conn:setlistener(websocket_listener);
	request.write("HTTP/1.1 101 Web Socket Protocol Handshake\r\n");
	request.write("Upgrade: WebSocket\r\n");
	request.write("Connection: Upgrade\r\n");
	request.write("WebSocket-Origin: file://\r\n"); -- FIXME
	request.write("WebSocket-Location: ws://localhost:5281/xmpp-websocket\r\n"); -- FIXME
	request.write("WebSocket-Protocol: XMPP\r\n");
	request.write("\r\n");

	return true;
end

local function setup()
	local ports = module:get_option("websocket_ports") or { 5281 };
	httpserver.new_from_config(ports, handle_request, { base = "xmpp-websocket" });
end
if prosody.start_time then -- already started
	setup();
else
	prosody.events.add_handler("server-started", setup);
end
