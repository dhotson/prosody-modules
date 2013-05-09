module:set_global();

local dm_load = require "util.datamanager".load;
local dm_store = require "util.datamanager".store;
local datetime = require "util.datetime".datetime;

local do_store = module:get_option_boolean(module:get_name().."_persist", false);
local digest_algo = module:get_option_string(module:get_name().."_digest", "sha1");

local function note_cert_digest(event)
	local session, remote_host, cert = event.session, event.host, event.cert;

	if not (remote_host and cert and cert.digest) then return end;
	local digest = cert:digest(digest_algo);

	local local_host = session.direction == "outgoing" and session.from_host or session.to_host;
	local chain_status = session.cert_chain_status;
	local identity_status = session.cert_identity_status;

	module:log("info", "Spotted %s %s certificate used by %s with %s: %s",
		chain_status == "valid" and "trusted" or "untrusted",
		identity_status or "invalid",
		remote_host, digest_algo:upper(),
		digest:upper():gsub("..",":%0"):sub(2));

	if do_store then
		local seen_certs = dm_load(remote_host, local_host, "s2s_certs") or {};

		digest = digest_algo..":"..digest;
		local this_cert = seen_certs[digest] or { first = datetime(); times = 0; }
		this_cert.last = datetime();
		this_cert.times = this_cert.times + 1;
		seen_certs[digest] = this_cert;
		chain_status = chain_status;
		identity_status = identity_status;
		dm_store(remote_host, local_host, "s2s_certs", seen_certs);
	end
end

module:hook("s2s-check-certificate", note_cert_digest, 1000);
--[[
function module.add_host(module)
	module:hook("s2s-check-certificate", note_cert_digest, 1000);
end
]]
