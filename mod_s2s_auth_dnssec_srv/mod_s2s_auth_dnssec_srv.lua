-- Copyright (C) 2013 Kim Alvefur
-- This file is MIT/X11 licensed.
--
-- Implements Secure Delegation using DNS SRV as described in
-- http://tools.ietf.org/html/draft-miller-xmpp-dnssec-prooftype
--
-- Dependecies:
-- Prosody above hg:43059357b2f0
-- DNSSEC-validating DNS resolver
--  https://github.com/Zash/luaunbound
--   libunbound binding using LuaJIT FFI

module:set_global();

local nameprep = require"util.encodings".stringprep.nameprep;
local to_unicode = require"util.encodings".idna.to_unicode;
local to_ascii = require "util.encodings".idna.to_ascii;
local cert_verify_identity = require "util.x509".verify_identity;
local dns_lookup = require"net.adns".lookup;
local t_insert = table.insert;

module:hook("s2s-check-certificate", function(event)
	local session, cert = event.session, event.cert;

	if session.cert_chain_status == "valid" and session.cert_identity_status ~= "valid"
	and session.srv_hosts.answer and session.srv_hosts.answer.secure then
		local srv_hosts, srv_choice, srv_target = session.srv_hosts, session.srv_choice;
		for i = srv_choice or 1, srv_choice or #srv_hosts do
			srv_target = nameprep(to_unicode(session.srv_hosts[i].target:gsub("%.?$","")));
			(session.log or module._log)("debug", "Comparing certificate with Secure SRV target %s", srv_target);
			if srv_target and cert_verify_identity(srv_target, "xmpp-server", cert) then
				(session.log or module._log)("info", "Certificate matches Secure SRV target %s", srv_target);
				session.cert_identity_status = "valid";
				return;
			end
		end
	end
end);

function module.add_host(module)
	module:hook("s2s-stream-features", function(event)
		local host_session = event.origin;
		local name = to_ascii(host_session.from_host);
		if not name then return end
		dns_lookup(function (answer)
			if host_session.dane ~= nil then return end
			if not answer.secure or #answer == 1
				and answer[1].srv.target == "." then return end
			local srv_hosts = { answer = answer };
			for _, record in ipairs(answer) do
				t_insert(srv_hosts, record.srv);
			end
			host_session.srv_hosts = srv_hosts;
		end, "_xmpp-server._tcp."..name..".", "SRV");
	end);
end

