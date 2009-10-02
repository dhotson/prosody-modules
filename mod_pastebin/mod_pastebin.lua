
local st = require "util.stanza";
local httpserver = require "net.httpserver";
local uuid_new = require "util.uuid".generate;
local os_time = os.time;

local length_threshold = config.get(module.host, "core", "pastebin_threshold") or 500;

local base_url = config.get(module.host, "core", "pastebin_url");

local pastes = {};

local xmlns_xhtmlim = "http://jabber.org/protocol/xhtml-im";
local xmlns_xhtml = "http://www.w3.org/1999/xhtml";

local function pastebin_message(text)
	local uuid = uuid_new();
	pastes[uuid] = { text = text, time = os_time() };
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
		elseif v.name == "html" and v.attr.xmlns == xmlns_xhtml then
			htmlindex = k;
		end
	end
	
	if not body then return; end
	body = body:get_text();
	
	module:log("debug", "Body(%s) length: %d", type(body), #(body or ""));
	
	if body and #body > length_threshold then
		local url = pastebin_message(body);
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
