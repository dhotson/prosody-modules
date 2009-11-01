
local st = require "util.stanza";
local httpserver = require "net.httpserver";
local uuid_new = require "util.uuid".generate;
local os_time = os.time;
local t_insert, t_remove = table.insert, table.remove;
local add_task = require "util.timer".add_task;

local length_threshold = config.get(module.host, "core", "pastebin_threshold") or 500;

local base_url = config.get(module.host, "core", "pastebin_url");

-- Seconds a paste should live for in seconds (config is in hours), default 24 hours
local expire_after = math.floor((config.get(module.host, "core", "pastebin_expire_after") or 24) * 3600);

local pastes = {};

local xmlns_xhtmlim = "http://jabber.org/protocol/xhtml-im";
local xmlns_xhtml = "http://www.w3.org/1999/xhtml";

function pastebin_text(text)
	local uuid = uuid_new();
	pastes[uuid] = { text = text, time = os_time() };
	pastes[#pastes+1] = uuid;
	if not pastes[2] then -- No other pastes, give the timer a kick
		add_task(expire_after, expire_pastes);
	end
	return base_url..uuid;
end

function handle_request(method, body, request)
	local pasteid = request.url.path:match("[^/]+$");
	if not pasteid or not pastes[pasteid] then
		return "Invalid paste id, perhaps it expired?";
	end
	
	--module:log("debug", "Received request, replying: %s", pastes[pasteid].text);
	
	return pastes[pasteid].text;
end

function check_message(data)
	local origin, stanza = data.origin, data.stanza;
	
	local body, bodyindex, htmlindex;
	for k,v in ipairs(stanza) do
		if v.name == "body" then
			body, bodyindex = v, k;
		elseif v.name == "html" and v.attr.xmlns == xmlns_xhtmlim then
			htmlindex = k;
		end
	end
	
	if not body then return; end
	body = body:get_text();
	
	--module:log("debug", "Body(%s) length: %d", type(body), #(body or ""));
	
	if body and #body > length_threshold then
		local url = pastebin_text(body);
		module:log("debug", "Pasted message as %s", url);		
		--module:log("debug", " stanza[bodyindex] = %q", tostring( stanza[bodyindex]));
		stanza[bodyindex][1] = url;
		local html = st.stanza("html", { xmlns = xmlns_xhtmlim }):tag("body", { xmlns = xmlns_xhtml });
		html:tag("p"):text(body:sub(1,150)):up();
		html:tag("a", { href = url }):text("[...]"):up();
		stanza[htmlindex or #stanza+1] = html;
	end
end

module:hook("message/bare", check_message);

function expire_pastes(time)
	time = time or os_time(); -- COMPAT with 0.5
	if pastes[1] then
		pastes[pastes[1]] = nil;
		t_remove(pastes, 1);
		if pastes[1] then
			return (expire_after - (time - pastes[pastes[1]].time)) + 1;
		end
	end
end


local ports = config.get(module.host, "core", "pastebin_ports") or { 5280 };
for _, options in ipairs(ports) do
	local port, base, ssl, interface = 5280, "pastebin", false, nil;
	if type(options) == "number" then
		port = options;
	elseif type(options) == "table" then
		port, base, ssl, interface = options.port or 5280, options.path or "pastebin", options.ssl or false, options.interface;
	elseif type(options) == "string" then
		base = options;
	end
	
	base_url = base_url or ("http://"..module:get_host()..(port ~= 80 and (":"..port) or "").."/"..base.."/");
	
	httpserver.new{ port = port, base = base, handler = handle_request, ssl = ssl }
end
