-- mod_s2s_auth_dane
-- Copyright (C) 2013-2014 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--
-- Implements DANE and Secure Delegation using DNS SRV as described in
-- http://tools.ietf.org/html/draft-miller-xmpp-dnssec-prooftype
--
-- Known issues:
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
local idna_to_unicode = require"util.encodings".idna.to_unicode;
local nameprep = require"util.encodings".stringprep.nameprep;
local cert_verify_identity = require "util.x509".verify_identity;

do
	local net_dns = require"net.dns";
	if not net_dns.types or not net_dns.types[52] then
		module:log("error", "No TLSA support available, DANE will not be supported");
		return
	end
end

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
if debug.getregistry()["SSL:Certificate"].__index.issued then
	-- Need cert:issued() for these
	implemented_uses:add("DANE-TA");
	implemented_uses:add("PKIX-CA");
else
	module:log("warn", "Unable to support DANE-TA and PKIX-CA");
end
local configured_uses = module:get_option_set("dane_uses", { "DANE-EE", "DANE-TA" });
local enabled_uses = set.intersection(implemented_uses, configured_uses) / function(use) return use_map[use] end;

local function dane_lookup(host_session, cb, a,b,c,e)
	if host_session.dane ~= nil then return end
	if host_session.direction == "incoming" then
		local name = host_session.from_host and idna_to_ascii(host_session.from_host);
		if not name then return end
		host_session.dane = dns_lookup(function (answer)
			host_session.dane = false;
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
						-- How to handle this?
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
			if answer and ((answer.secure and #answer > 0) or answer.bogus) then
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

function module.add_host(module)
	local function on_new_s2s(event)
		local host_session = event.origin;
		if host_session.type == "s2sout" or host_session.type == "s2sin" or host_session.dane ~= nil then return end -- Already authenticated
		host_session.log("debug", "Pausing connection until DANE lookup is completed");
		host_session.conn:pause()
		local function resume()
			host_session.log("debug", "DANE lookup completed, resuming connection");
			host_session.conn:resume()
		end
		if not dane_lookup(host_session, resume) then
			resume();
		end
	end

	-- New outgoing connections
	module:hook("stanza/http://etherx.jabber.org/streams:features", on_new_s2s, 501);
	module:hook("s2sout-authenticate-legacy", on_new_s2s, 200);

	-- New incoming connections
	module:hook("s2s-stream-features", on_new_s2s, 10);

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
		-- Cleanup
		session.dane = nil;
		session.srv_hosts = nil;
	end);
end

local function one_dane_check(tlsa, cert)
	local select, match, certdata = tlsa.select, tlsa.match;

	if select == 0 then
		certdata = pem2der(cert:pem());
	elseif select == 1 and cert.pubkey then
		certdata = pem2der(cert:pubkey());
	else
		module:log("warn", "DANE selector %s is unsupported", tlsa:getSelector() or select);
		return;
	end

	if match == 1 then
		certdata = hashes.sha256(certdata);
	elseif match == 2 then
		certdata = hashes.sha512(certdata);
	elseif match ~= 0 then
		module:log("warn", "DANE match rule %s is unsupported", tlsa:getMatchType() or match);
		return;
	end

	return certdata == tlsa.data;
end

module:hook("s2s-check-certificate", function(event)
	local session, cert = event.session, event.cert;
	local dane = session.dane;
	if type(dane) == "table" then
		local use, tlsa, match_found, supported_found, chain, leafcert, cacert, is_match;
		for i = 1, #dane do
			tlsa = dane[i].tlsa;
			module:log("debug", "TLSA %s %s %s %d bytes of data", tlsa:getUsage(), tlsa:getSelector(), tlsa:getMatchType(), #tlsa.data);
			use = tlsa.use;

			if enabled_uses:contains(use) then
				-- PKIX-EE or DANE-EE
				if use == 1 or use == 3 then
					-- Should we check if the cert subject matches?
					is_match = one_dane_check(tlsa, cert);
					if is_match ~= nil then
						supported_found = true;
					end
					if is_match then
						(session.log or module._log)("info", "DANE validation successful");
						session.cert_identity_status = "valid";
						if use == 3 then -- DANE-EE, chain status equals DNSSEC chain status
							session.cert_chain_status = "valid";
							-- for usage 1, PKIX-EE, the chain has to be valid already
						end
						match_found = true;
						break;
					end
				elseif use == 0 or use == 2 then
					supported_found = true;
					if chain == nil then
						chain = session.conn:socket():getpeerchain();
					end
					for i = 2, #chain do
						cacert, leafcert = chain[i], chain[i-1];
						is_match = one_dane_check(tlsa, cacert);
						if is_match ~= nil then
							supported_found = true;
						end
						if use == 2 and not cacert:issued(leafcert or cacert) then
							module:log("debug", "Broken chain");
							break;
						end
						if is_match then
							(session.log or module._log)("info", "DANE validation successful");
							if use == 2 then -- DANE-TA
								session.cert_identity_status = "valid";
								session.cert_chain_status = "valid";
								-- for usage 0, PKIX-CA, identity and chain has to be valid already
							end
							match_found = true;
							break;
						end
					end
					if match_found then break end
				end
			end
		end
		if supported_found and not match_found or dane.bogus then
			-- No TLSA matched or response was bogus
			(session.log or module._log)("warn", "DANE validation failed");
			session.cert_identity_status = "invalid";
			session.cert_chain_status = "invalid";
		end
	else
		if session.cert_chain_status == "valid" and session.cert_identity_status ~= "valid"
		and session.srv_hosts and session.srv_hosts.answer and session.srv_hosts.answer.secure then
			local srv_hosts, srv_choice, srv_target = session.srv_hosts, session.srv_choice;
			for i = srv_choice or 1, srv_choice or #srv_hosts do
				srv_target = nameprep(idna_to_unicode(session.srv_hosts[i].target:gsub("%.?$","")));
				(session.log or module._log)("debug", "Comparing certificate with Secure SRV target %s", srv_target);
				if srv_target and cert_verify_identity(srv_target, "xmpp-server", cert) then
					(session.log or module._log)("info", "Certificate matches Secure SRV target %s", srv_target);
					session.cert_identity_status = "valid";
					return;
				end
			end
		end
	end
end);

