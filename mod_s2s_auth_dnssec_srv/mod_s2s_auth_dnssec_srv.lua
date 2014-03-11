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
local cert_verify_identity = require "util.x509".verify_identity;

module:hook("s2s-check-certificate", function(event)
	local session, cert = event.session, event.cert;

	if session.cert_chain_status == "valid" and session.cert_identity_status ~= "valid"
	and session.srv_choice and session.srv_hosts.answer and session.srv_hosts.answer.secure then
		local srv_target = nameprep(to_unicode(session.srv_hosts[session.srv_choice].target:gsub("%.?$","")));
		(session.log or module._log)("debug", "Comparing certificate with Secure SRV target %s", srv_target);
		if srv_target and cert_verify_identity(srv_target, "xmpp-server", cert) then
			(session.log or module._log)("info", "Certificate matches Secure SRV target %s", srv_target);
			session.cert_identity_status = "valid";
		end
	end
end);
