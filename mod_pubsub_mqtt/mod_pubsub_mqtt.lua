module:set_global();

local mqtt = module:require "mqtt";
local st = require "util.stanza";

local pubsub_services = {};
local pubsub_subscribers = {};
local packet_handlers = {};

function handle_packet(session, packet)
	module:log("warn", "MQTT packet received! Length: %d", packet.length);
	for k,v in pairs(packet) do
		module:log("debug", "MQTT %s: %s", tostring(k), tostring(v));
	end
	local handler = packet_handlers[packet.type];
	if not handler then
		module:log("warn", "Unhandled command: %s", tostring(packet.type));
		return;
	end
	handler(session, packet);
end

function packet_handlers.connect(session, packet)
	session.conn:write(mqtt.serialize_packet{
		type = "connack";
		data = string.char(0x00, 0x00);
	});
end

function packet_handlers.disconnect(session, packet)
	session.conn:close();
end

function packet_handlers.publish(session, packet)
	module:log("warn", "PUBLISH to %s", packet.topic);
	local host, node = packet.topic:match("^([^/]+)/(.+)$");
	local pubsub = pubsub_services[host];
	if not pubsub then
		module:log("warn", "Unable to locate host/node: %s", packet.topic);
		return;
	end
	local id = "mqtt";
	local ok, err = pubsub:publish(node, true, id,
		st.stanza("data", { xmlns = "https://prosody.im/protocol/mqtt" })
			:text(packet.data)
	);
	if not ok then
		module:log("warn", "Error publishing MQTT data: %s", tostring(err));
	end
end

function packet_handlers.subscribe(session, packet)
	for _, topic in ipairs(packet.topics) do
		module:log("warn", "SUBSCRIBE to %s", topic);
		local host, node = topic:match("^([^/]+)/(.+)$");
		local pubsub = pubsub_subscribers[host];
		if not pubsub then
			module:log("warn", "Unable to locate host/node: %s", topic);
			return;
		end
		local node_subs = pubsub[node];
		if not node_subs then
			node_subs = {};
			pubsub[node] = node_subs;
		end
		session.subscriptions[topic] = true;
		node_subs[session] = true;
	end
	
end

function packet_handlers.pingreq(session, packet)
	session.conn:write(mqtt.serialize_packet{type = "pingresp"});
end

local sessions = {};

local mqtt_listener = {};

function mqtt_listener.onconnect(conn)
	sessions[conn] = {
		conn = conn;
		stream = mqtt.new_stream();
		subscriptions = {};
	};
end

function mqtt_listener.onincoming(conn, data)
	local session = sessions[conn];
	if session then
		local packets = session.stream:feed(data);
		for i = 1, #packets do
			handle_packet(session, packets[i]);
		end
	end
end

function mqtt_listener.ondisconnect(conn)
	local session = sessions[conn];
	for topic in pairs(session.subscriptions) do
		local host, node = topic:match("^([^/]+)/(.+)$");
		local subs = pubsub_subscribers[host];
		if subs then
			local node_subs = subs[node];
			if node_subs then
				node_subs[session] = nil;
			end
		end
	end
	sessions[conn] = nil;
	module:log("debug", "MQTT client disconnected");
end

module:provides("net", {
	default_port = 1883;
	listener = mqtt_listener;
});

local function tostring_content(item)
	return tostring(item[1]);
end

local data_translators = setmetatable({
	["data https://prosody.im/protocol/mqtt"] = tostring_content;
	["json urn:xmpp:json:0"] = tostring_content;
}, {
	__index = function () return tostring; end;
});

function module.add_host(module)
	local pubsub_module = hosts[module.host].modules.pubsub
	if pubsub_module then
		module:log("debug", "MQTT enabled for %s", module.host);
		module:depends("pubsub");
		pubsub_services[module.host] = assert(pubsub_module.service);
		local subscribers = {};
		pubsub_subscribers[module.host] = subscribers;
		local function handle_publish(event)
			-- Build MQTT packet
			local packet = mqtt.serialize_packet{
				type = "publish";
				id = "\000\000";
				topic = module.host.."/"..event.node;
				data = data_translators[event.item.name.." "..event.item.attr.xmlns](event.item);
			};
			-- Broadcast to subscribers
			module:log("debug", "Broadcasting PUBLISH to subscribers of %s/%s", module.host, event.node);
			for session in pairs(subscribers[event.node] or {}) do
				session.conn:write(packet);
				module:log("debug", "Sent to %s", tostring(session));
			end
		end
		pubsub_services[module.host].events.add_handler("item-published", handle_publish);
		function module.unload()
			module:log("debug", "MQTT disabled for %s", module.host);
			pubsub_module.service.remove_handler("item-published", handle_publish);
			pubsub_services[module.host] = nil;
			pubsub_subscribers[module.host] = nil;
		end
	end
end
