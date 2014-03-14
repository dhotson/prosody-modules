-- mod_s2s_auth_dane
-- Copyright (C) 2013-2014 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--
-- In your DNS, put
-- _xmpp-server.example.com. IN TLSA 3 0 1 <sha256 hash of certificate>
--
-- Known issues:
-- Race condition
-- Could be done much cleaner if mod_s2s was using util.async
--
-- TODO Things to test/handle:
-- Negative or bogus answers
-- No encryption offered
-- Different hostname before and after STARTTLS - mod_s2s should complain
-- Interaction with Dialback

module:set_global();

local type = type;
local set = require"util.set";
local dns_lookup = require"net.adns".lookup;
local hashes = require"util.hashes";
local base64 = require"util.encodings".base64;
local idna_to_ascii = require "util.encodings".idna.to_ascii;

local s2sout = module:depends"s2s".route_to_new_session.s2sout;

local bogus = {};

local pat = "%-%-%-%-%-BEGIN ([A-Z ]+)%-%-%-%-%-\r?\n"..
"([0-9A-Za-z=+/\r\n]*)\r?\n%-%-%-%-%-END %1%-%-%-%-%-";
local function pem2der(pem)
	local typ, data = pem:match(pat);
	if typ and data then
		return base64.decode(data), typ;
	end
end
local use_map = { ["DANE-EE"] = 3; ["DANE-TA"] = 2; ["PKIX-EE"] = 1; ["PKIX-CA"] = 0 }

local implemented_uses = set.new { "DANE-EE", "PKIX-EE" };
local configured_uses = module:get_option_set("dane_uses", { "DANE-EE" });
local enabled_uses = set.intersection(implemented_uses, configured_uses) / function(use) return use_map[use] end;

local function dane_lookup(host_session, name, cb, a,b,c)
	if host_session.dane ~= nil then return false; end
	local ascii_host = name and idna_to_ascii(name);
	if not ascii_host then return false; end
	host_session.dane = dns_lookup(function(answer)
		if answer and (answer.secure and #answer > 0) then
			host_session.dane = answer;
		elseif answer.bogus then
			host_session.dane = bogus;
		else
			host_session.dane = false;
		end
		if cb then return cb(a,b,c); end
	end, ("_xmpp-server.%s."):format(ascii_host), "TLSA");
	host_session.connecting = true;
	return true;
end

local _attempt_connection = s2sout.attempt_connection;
function s2sout.attempt_connection(host_session, err)
	if not err and dane_lookup(host_session, host_session.to_host, _attempt_connection, host_session, err) then
		return true;
	end
	return _attempt_connection(host_session, err);
end

function module.add_host(module)
	module:hook("s2s-stream-features", function(event)
		local origin = event.origin;
		dane_lookup(origin, origin.from_host);
	end, 1);

	module:hook("s2s-authenticated", function(event)
		local session = event.session;
		if session.dane and not session.secure then
			-- TLSA record but no TLS, not ok.
			-- TODO Optional?
			-- Bogus replies should trigger this path
			-- How does this interact with Dialback?
			session:close({
				condition = "policy-violation",
				text = "Encrypted server-to-server communication is required but was not "
					..((session.direction == "outgoing" and "offered") or "used")
			});
			return false;
		end
	end);
end

module:hook("s2s-check-certificate", function(event)
	local session, cert = event.session, event.cert;
	local dane = session.dane;
	if type(dane) == "table" then
		local use, select, match, tlsa, certdata, match_found, supported_found;
		for i = 1, #dane do
			tlsa = dane[i].tlsa;
			module:log("debug", "TLSA %s %s %s %d bytes of data", tlsa:getUsage(), tlsa:getSelector(), tlsa:getMatchType(), #tlsa.data);
			use, select, match, certdata = tlsa.use, tlsa.select, tlsa.match;

			if enabled_uses:contains(use) then
				-- PKIX-EE or DANE-EE
				if use == 1 or use == 3 then
					supported_found = true

					if select == 0 then
						certdata = pem2der(cert:pem());
					elseif select == 1 and cert.pubkey then
						certdata = pem2der(cert:pubkey()); -- Not supported in stock LuaSec
					else
						module:log("warn", "DANE selector %s is unsupported", tlsa:getSelector() or select);
					end

					if match == 1 then
						certdata = hashes.sha256(certdata);
					elseif match == 2 then
						certdata = hashes.sha512(certdata);
					elseif match ~= 0 then
						module:log("warn", "DANE match rule %s is unsupported", tlsa:getMatchType() or match);
						certdata = nil;
					end

					-- Should we check if the cert subject matches?
					if certdata and certdata == tlsa.data then
						(session.log or module._log)("info", "DANE validation successful");
						session.cert_identity_status = "valid";
						if use == 3 then -- DANE-EE, chain status equals DNSSEC chain status
							session.cert_chain_status = "valid";
							-- for usage 1, PKIX-EE, the chain has to be valid already
						end
						match_found = true;
						break;
					end
				end
			end
		end
		if supported_found and not match_found or dane.bogus then
			-- No TLSA matched or response was bogus
			(session.log or module._log)("warn", "DANE validation failed");
			session.cert_identity_status = "invalid";
			session.cert_chain_status = "invalid";
		end
	end
end);

function module.unload()
	-- Restore the original attempt_connection function
	s2sout.attempt_connection = _attempt_connection;
end

