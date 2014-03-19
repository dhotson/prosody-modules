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
local t_insert = table.insert;
local set = require"util.set";
local dns_lookup = require"net.adns".lookup;
local hashes = require"util.hashes";
local base64 = require"util.encodings".base64;
local idna_to_ascii = require "util.encodings".idna.to_ascii;

if not dns_lookup.types or not dns_lookup.types.TLSA then
	module:log("error", "No TLSA support available, DANE will not be supported");
	return
end

local s2sout = module:depends"s2s".route_to_new_session.s2sout;

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

local function dane_lookup(host_session, cb, a,b,c,e)
	if host_session.dane ~= nil then return end
	if host_session.direction == "incoming" then
		local name = idna_to_ascii(host_session.from_host);
		if not name then return end
		host_session.dane = dns_lookup(function (answer)
			if not answer.secure then
				if cb then return cb(a,b,c,e); end
				return;
			end
			local n = #answer
			if n == 0 then if cb then return cb(a,b,c,e); end return end
			if n == 1 and answer[1].srv.target == '.' then return end
			local srv_hosts = { answer = answer };
			local dane = {};
			host_session.dane = dane;
			host_session.srv_hosts = srv_hosts;
			for _, record in ipairs(answer) do
				t_insert(srv_hosts, record.srv);
				dns_lookup(function(dane_answer)
					n = n - 1;
					if dane_answer.bogus then
						t_insert(dane, { bogus = dane_answer.bogus });
					elseif dane_answer.secure then
						for _, record in ipairs(dane_answer) do
							t_insert(dane, record);
						end
					end
					if n == 0 and cb then return cb(a,b,c,e); end
				end, ("_%d._tcp.%s."):format(record.srv.port, record.srv.target), "TLSA");
			end
		end, "_xmpp-server._tcp."..name..".", "SRV");
		return true;
	elseif host_session.direction == "outgoing" then
		local srv_hosts = host_session.srv_hosts;
		if not ( srv_hosts and srv_hosts.answer and srv_hosts.answer.secure )  then return end
		local srv_choice = srv_hosts[host_session.srv_choice];
		host_session.dane = dns_lookup(function(answer)
			if answer and (answer.secure and #answer > 0) or answer.bogus then
				srv_choice.dane = answer;
			else
				srv_choice.dane = false;
			end
			host_session.dane = srv_choice.dane;
			if cb then return cb(a,b,c,e); end
		end, ("_%d._tcp.%s."):format(srv_choice.port, srv_choice.target), "TLSA");
		return true;
	end
end

local _try_connect = s2sout.try_connect;
function s2sout.try_connect(host_session, connect_host, connect_port, err)
	if not err and dane_lookup(host_session, _try_connect, host_session, connect_host, connect_port, err) then
		return true;
	end
	return _try_connect(host_session, connect_host, connect_port, err);
end

function module.add_host(module)
	module:hook("s2s-stream-features", function(event)
		-- dane_lookup(origin, origin.from_host);
		dane_lookup(event.origin);
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
						certdata = certdata and hashes.sha256(certdata);
					elseif match == 2 then
						certdata = certdata and hashes.sha512(certdata);
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
	-- Restore the original try_connect function
	s2sout.try_connect = _try_connect;
end

