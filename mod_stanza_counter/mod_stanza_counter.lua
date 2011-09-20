-- (C) 2011, Marco Cirillo (LW.Org)
-- General Stanzas' Counter with web output.

local jid_bare = require "util.jid".bare
local httpserver = require "net.httpserver"

local ports = module:get_option_array("stanza_counter_ports" or {{ port = 5280 }})

-- http handlers

local r_200 = "\n<html>\n<head>\n<title>Prosody's Stanza Counter</title>\n<meta name=\"robots\" content=\"noindex, nofollow\" />\n</head>\n\n<body>\n<h3>Incoming and Outgoing stanzas divided per type</h3>\n<p><strong>Incoming IQs</strong>: %d<br/>\n<strong>Outgoing IQs</strong>: %d<br/>\n<strong>Incoming Messages</strong>: %d<br/>\n<strong>Outgoing Messages</strong>: %d<br/>\n<strong>Incoming Presences</strong>: %d<br/>\n<strong>Outgoing Presences</strong>: %d<p>\n</body>\n\n</html>\n"

local r_405 = "\n<html>\n<head>\n<title>Prosody's Stanza Counter - Error</title>\n<meta name=\"robots\" content=\"noindex, nofollow\" />\n</head>\n\n<body>\n<h3>Bad Method ... I only support GET.</h3>\n</body>\n\n</html>\n"

local function res(code, r, h)
	local response = {
		status = code;
		body = r;
		}
	
        if h then response.headers = h; end
        return response
end

local function req(method, body, request)
	if method == "GET" then
		local forge_res = r_200:format(prosody.stanza_counter.iq["incoming"],
					       prosody.stanza_counter.iq["outgoing"],
					       prosody.stanza_counter.message["incoming"],
					       prosody.stanza_counter.message["outgoing"],
					       prosody.stanza_counter.presence["incoming"],
					       prosody.stanza_counter.presence["outgoing"]);
		return res(200, forge_res)
	else
		return res(405, r_405, {["Allow"] = "GET"})
	end
end

-- Setup, Init functions.
-- initialize function counter table on the global object on start
local function init_counter()
	prosody.stanza_counter = { 
		iq = { incoming=0, outgoing=0 },
		message = { incoming=0, outgoing=0 },
		presence = { incoming=0, outgoing=0 }
	}
end

-- init http interface
local function init_web()
	httpserver.new_from_config(ports, req, { base = "stanza-counter" })
end

-- Setup on server start
local function setup()
	init_counter(); init_web();
end

-- Basic Stanzas' Counters
local function iq_callback(check)
	return function(self)
		local origin, stanza = self.origin, self.stanza
		if not prosody.stanza_counter then init_counter() end
		if check then
			if not stanza.attr.to or hosts[jid_bare(stanza.attr.to)] then return nil;
			else
				prosody.stanza_counter.iq["outgoing"] = prosody.stanza_counter.iq["outgoing"] + 1
			end
		else
			prosody.stanza_counter.iq["incoming"] = prosody.stanza_counter.iq["incoming"] + 1
		end
	end
end

local function mes_callback(check)
	return function(self)
		local origin, stanza = self.origin, self.stanza
		if not prosody.stanza_counter then init_counter() end
		if check then
			if not stanza.attr.to or hosts[jid_bare(stanza.attr.to)] then return nil;
			else
				prosody.stanza_counter.message["outgoing"] = prosody.stanza_counter.message["outgoing"] + 1
			end
		else
			prosody.stanza_counter.message["incoming"] = prosody.stanza_counter.message["incoming"] + 1
		end
	end
end

local function pre_callback(check)
	return function(self)
		local origin, stanza = self.origin, self.stanza
		if not prosody.stanza_counter then init_counter() end
		if check then
			if not stanza.attr.to or hosts[jid_bare(stanza.attr.to)] then return nil;
			else
				prosody.stanza_counter.presence["outgoing"] = prosody.stanza_counter.presence["outgoing"] + 1
			end
		else
			prosody.stanza_counter.presence["incoming"] = prosody.stanza_counter.presence["incoming"] + 1
		end
	end
end



-- Hook all pre-stanza events.
module:hook("pre-iq/bare", iq_callback(true), 140)
module:hook("pre-iq/full", iq_callback(true), 140)
module:hook("pre-iq/host", iq_callback(true), 140)

module:hook("pre-message/bare", mes_callback(true), 140)
module:hook("pre-message/full", mes_callback(true), 140)
module:hook("pre-message/host", mes_callback(true), 140)

module:hook("pre-presence/bare", pre_callback(true), 140)
module:hook("pre-presence/full", pre_callback(true), 140)
module:hook("pre-presence/host", pre_callback(true), 140)

-- Hook all stanza events.
module:hook("iq/bare", iq_callback(false), 140)
module:hook("iq/full", iq_callback(false), 140)
module:hook("iq/host", iq_callback(false), 140)

module:hook("message/bare", mes_callback(false), 140)
module:hook("message/full", mes_callback(false), 140)
module:hook("message/host", mes_callback(false), 140)

module:hook("presence/bare", pre_callback(false), 140)
module:hook("presence/full", pre_callback(false), 140)
module:hook("presence/host", pre_callback(false), 140)

-- Hook server start to initialize the counter.
module:hook("server-started", setup)
