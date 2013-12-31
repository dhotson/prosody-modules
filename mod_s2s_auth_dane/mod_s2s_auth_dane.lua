-- mod_s2s_auth_dane
--
-- Between the DNS lookup and the chertificate validation, there is a race condition.
-- Solving that probably requires changes to mod_s2s, like using util.async


module:set_global();

local dns_lookup = require"net.adns".lookup;
local hashes = require"util.hashes";
local base64 = require"util.encodings".base64;

local s2sout = module:depends"s2s".route_to_new_session.s2sout;
local _try_connect = s2sout.try_connect

local pat = "%-%-%-%-%-BEGIN ([A-Z ]+)%-%-%-%-%-\r?\n"..
"([0-9A-Za-z=+/\r\n]*)\r?\n%-%-%-%-%-END %1%-%-%-%-%-";
local function pem2der(pem)
	local typ, data = pem:match(pat);
	if typ and data then
		return base64.decode(data), typ;
	end
end

-- TODO Things to test/handle:
-- Negative or bogus answers
-- No SRV records

function s2sout.try_connect(host_session, connect_host, connect_port, err)
	local srv_hosts = host_session.srv_hosts;
	local srv_choice = host_session.srv_choice;
	if srv_hosts and srv_hosts.answer.secure and not srv_hosts[srv_choice].dane then
		dns_lookup(function(answer)
			if answer and #answer > 0 then
				srv_hosts[srv_choice].dane = answer;
				for i, tlsa in ipairs(answer) do
					module:log("debug", "TLSA %s", tostring(tlsa));
				end
			end
		end, ("_%d._tcp.%s"):format(connect_port, connect_host), "TLSA")
	end
	return _try_connect(host_session, connect_host, connect_port, err)
end

module:hook("s2s-check-certificate", function(event)
	local session, cert = event.session, event.cert;
	local srv_hosts = session.srv_hosts;
	local srv_choice = session.srv_choice;
	local choosen = srv_hosts and srv_hosts[srv_choice];
	if choosen and choosen.dane then
		local use, select, match, tlsa, certdata
		for i, rr in ipairs(choosen.dane) do
			tlsa = rr.tlsa
			module:log("debug", "TLSA %s", tostring(tlsa));
			use, select, match, certdata = tlsa.use, tlsa.select, tlsa.match;

			if use == 1 or use == 3 then

				if select == 0 then
					certdata = pem2der(cert:pem());
				elseif select == 1 then
					certdata = pem2der(cert:pubkey());
				end
				if match == 1 then
					certdata = hashes.sha256(certdata);
				elseif match == 2 then
					certdata = hashes.sha512(certdata);
				end

				-- Should we check if the cert subject matches?
				if certdata == tlsa.data then
					(session.log or module._log)("info", "DANE validation successful");
					session.cert_identity_status = "valid"
					if use == 3 then
						session.cert_chain_status = "valid"
						-- for usage 1 the chain has to be valid already
					end
					break;
				end
			else
				module:log("warn", "DANE %s is unsupported", tlsa:getUsage());
				-- TODO Ca checks needs to loop over the chain and stuff
			end
		end
	end

	-- TODO Optionally, if no TLSA record matches, mark connection as untrusted.
end);

function module.unload()
	s2sout.try_connect = _try_connect;
end

