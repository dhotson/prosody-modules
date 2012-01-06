-- (C) 2011, Marco Cirillo (LW.Org)
-- Display server stats in readable XML format

module:set_global()

local ports = module:get_option_array("xml_status_http_ports", {{ port = 5280 }})
local show_hosts = module:get_option_array("xml_status_show_hosts", nil)
local show_comps = module:get_option_array("xml_status_show_comps", nil)

local httpserver = require "net.httpserver"

-- code begin

if not prosody.stanza_counter and not show_hosts and not show_comps then
	module:log ("error", "mod_xml_status requires at least one of the following things:")
	module:log ("error", "mod_stanza_counter loaded, or either xml_status_show_hosts or xml_status_show_comps configuration values set.")
	module:log ("error", "check the module wiki at: http://code.google.com/p/prosody-modules/wiki/mod_xml_status")
	return false
end

local r_err = "\n<html>\n<head>\n<title>Prosody's XML Status - Error %s</title>\n<meta name=\"robots\" content=\"noindex, nofollow\" />\n</head>\n\n<body>\n<h3>%s</h3>\n</body>\n\n</html>\n"

local response_table = {}
response_table.header = '<?xml version="1.0" encoding="UTF-8" ?>'
response_table.doc_header = '<document>'
response_table.doc_closure = '</document>'
response_table.stanzas = {
		elem_header = '  <stanzas>', elem_closure = '  </stanzas>',
		incoming = '    <incoming iq="%d" message="%d" presence="%d" />', 
		outgoing = '    <outgoing iq="%d" message="%d" presence="%d" />'
}
response_table.hosts = {
		elem_header = '  <hosts>', elem_closure = '  </hosts>',
		status = '    <status name="%s" current="%s" />'
}
response_table.comps = {
		elem_header = '  <components>', elem_closure = '  </components>',
		status = '    <status name="%s" current="%s" />'
}

local function forge_response()
	local hosts_s = {}; local components = {}; local stats = {}; local hosts_stats = {}; local comps_stats = {}

	-- add headers
	local result = {}; result[#result+1] = response_table.header; result[#result+1] = response_table.doc_header
	
	if show_hosts then for _, name in ipairs(show_hosts) do hosts_s[#hosts_s+1] = name end end
	if show_comps then for _, name in ipairs(show_comps) do components[#components+1] = name end end
	
	-- build stanza stats if there
	if prosody.stanza_counter then
		stats[1] = response_table.stanzas.elem_header
		stats[2] = response_table.stanzas.incoming:format(prosody.stanza_counter.iq["incoming"],
								  prosody.stanza_counter.message["incoming"],
								  prosody.stanza_counter.presence["incoming"])
		stats[3] = response_table.stanzas.outgoing:format(prosody.stanza_counter.iq["outgoing"],
								  prosody.stanza_counter.message["outgoing"],
								  prosody.stanza_counter.presence["outgoing"])
		stats[4] = response_table.stanzas.elem_closure
	end

	-- build hosts stats if there
	if hosts_s[1] then
		hosts_stats[1] = response_table.hosts.elem_header
		for _, name in ipairs(hosts_s) do 
			hosts_stats[#hosts_stats+1] = response_table.hosts.status:format(
				name, hosts[name] and "online" or "offline")
		end
		hosts_stats[#hosts_stats+1] = response_table.hosts.elem_closure
	end

	-- build components stats if there
	if components[1] then
		comps_stats[1] = response_table.comps.elem_header
		for _, name in ipairs(components) do 
			comps_stats[#comps_stats+1] = response_table.comps.status:format(
				name, hosts[name].modules.component and hosts[name].modules.component.connected and "online" or 
				hosts[name] and hosts[name].modules.component == nil and "online" or "offline")
		end
		comps_stats[#comps_stats+1] = response_table.comps.elem_closure
	end

	-- finish building xml stats document
	for _, bstring in ipairs(stats) do result[#result+1] = bstring end
	for _, bstring in ipairs(hosts_stats) do result[#result+1] = bstring end
	for _, bstring in ipairs(comps_stats) do result[#result+1] = bstring end
	result[#result+1] = response_table.doc_closure

	return table.concat(result, "\n")
end

-- http handlers

local function response(code, r, h)
	local response = {
		status = code;
		body = r;
		}
	
        if h then response.headers = h; end
        return response
end

local function request(method, body, request)
	if not prosody.stanza_counter then
		local err500 = r_err:format("500", "Internal server error")
		return response(500, err500) end
	if method == "GET" then
		return response(200, forge_response())
	else
		local err405 = r_err:format("405", "Only GET is supported")
		return response(405, err405, {["Allow"] = "GET"})
	end
end

-- initialization.
-- init http interface
local function setup()
	httpserver.new_from_config(ports, request, { base = "xml-status" })
end

if prosody.start_time then
        setup();
else
        module:hook("server-started", setup);
end
