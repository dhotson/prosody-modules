-- http://legastero.github.io/customxeps/extensions/xep-0156.html

module:depends"http";

local json = require"util.json";
local st = require"util.stanza";

local host_modules = hosts[module.host].modules;

local function GET_xml(event)
	local request, response = event.request, event.response;
	local xrd = st.stanza("XRD", { xmlns='http://docs.oasis-open.org/ns/xri/xrd-1.0' });
	if host_modules["bosh"] then
		xrd:tag("Link", { rel="urn:xmpp:altconnect:bosh", href = module:http_url("bosh", "/http-bind") }):up();
	end
	if host_modules["websocket"] then
		xrd:tag("Link", { rel="urn:xmpp:altconnect:websocket", href = module:http_url("bosh", "/xmpp-websocket"):gsub("^http", "ws") }):up();
	end
	response.headers.content_type = "application/xrd+xml"
	response.headers.access_control_allow_origin = "*";
	return tostring(xrd);
end

local function GET_json(event)
	local request, response = event.request, event.response;
	local jrd = { links = { } };
	if host_modules["bosh"] then
		jrd.links[#jrd.links+1] = { rel="urn:xmpp:altconnect:bosh", href = module:http_url("bosh", "/http-bind") };
	end
	if host_modules["websocket"] then
		jrd.links[#jrd.links+1] = { rel="urn:xmpp:altconnect:websocket", href = module:http_url("bosh", "/xmpp-websocket"):gsub("^http", "ws") }
	end
	response.headers.content_type = "application/json"
	response.headers.access_control_allow_origin = "*";
	return json.encode(jrd);
end;

local function GET_either(event)
	local accept_type = event.request.headers.accept or "";
	if ( accept_type:find("xml") or #accept_type ) < ( accept_type:find("json") or #accept_type+1 ) then
		return GET_xml(event);
	else
		return GET_json(event);
	end
end;

module:provides("http", {
	default_path = "/.well-known";
	route = {
		["GET /host-meta"] = GET_either;
		-- ["GET /host-meta.xml"] = GET_xml; -- Hmmm
		["GET /host-meta.json"] = GET_json;
	};
});
