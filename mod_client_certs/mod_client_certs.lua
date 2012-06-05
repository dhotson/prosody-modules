-- XEP-0257: Client Certificates Management implementation for Prosody
-- Copyright (C) 2012 Thijs Alkemade
--
-- This file is MIT/X11 licensed.

local st = require "util.stanza";
local jid_bare = require "util.jid".bare;
local xmlns_saslcert = "urn:xmpp:saslcert:0";
local xmlns_pubkey = "urn:xmpp:tmp:pubkey";
local dm_load = require "util.datamanager".load;
local dm_store = require "util.datamanager".store;
local dm_table = "client_certs";
local x509 = require "ssl.x509";
local id_on_xmppAddr = "1.3.6.1.5.5.7.8.5";
local digest_algo = "sha1";

local function enable_cert(username, cert, info)
	local certs = dm_load(username, module.host, dm_table) or {};
	local all_certs = dm_load(nil, module.host, dm_table) or {};

	info.pem = cert:pem();
	local digest = cert:digest(digest_algo);
	info.digest = digest;
	certs[info.id] = info;
	all_certs[digest] = username;
	-- Or, have it be keyed by the entire PEM representation

	dm_store(username, module.host, dm_table, certs);
	dm_store(nil, module.host, dm_table, all_certs);
	return true
end

local function disable_cert(username, name)
	local certs = dm_load(username, module.host, dm_table) or {};
	local all_certs = dm_load(nil, module.host, dm_table) or {};

	local info = certs[name];
	local cert;
	if info then
		certs[name] = nil;
		cert = x509.cert_from_pem(info.pem);
		all_certs[cert:digest(digest_algo)] = nil;
	else
		return nil, "item-not-found"
	end

	dm_store(username, module.host, dm_table, certs);
	dm_store(nil, module.host, dm_table, all_certs);
	return cert; -- So we can compare it with stuff
end

module:hook("iq/self/"..xmlns_saslcert..":items", function(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type == "get" then
		module:log("debug", "%s requested items", origin.full_jid);

		local reply = st.reply(stanza):tag("items", { xmlns = xmlns_saslcert });
		local certs = dm_load(origin.username, module.host, dm_table) or {};

		for digest,info in pairs(certs) do
			reply:tag("item", { id = info.id })
				:tag("name"):text(info.name):up()
				:tag("keyinfo", { xmlns = xmlns_pubkey }):tag("name"):text(info["key_name"]):up()
				:tag("x509cert"):text(info.x509cert)
			:up();
		end

		origin.send(reply);
		return true
	end
end);

module:hook("iq/self/"..xmlns_saslcert..":append", function(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type == "set" then

		local append = stanza:get_child("append", xmlns_saslcert);
		local name = append:get_child_text("name", xmlns_saslcert);
		local key_info = append:get_child("keyinfo", xmlns_pubkey);

		if not key_info or not name then
			origin.send(st.error_reply(stanza, "cancel", "bad-request", "Missing fields.")); -- cancel? not modify?
			return true
		end
		
		local id = key_info:get_child_text("name", xmlns_pubkey);
		local x509cert = key_info:get_child_text("x509cert", xmlns_pubkey);

		if not id or not x509cert then
			origin.send(st.error_reply(stanza, "cancel", "bad-request", "No certificate found."));
			return true
		end

		local can_manage = key_info:get_child("no-cert-management", xmlns_saslcert) ~= nil;
		local x509cert = key_info:get_child_text("x509cert");

		local cert = x509.cert_from_pem(
		"-----BEGIN CERTIFICATE-----\n"
		.. x509cert ..
		"\n-----END CERTIFICATE-----\n");


		if not cert then
			origin.send(st.error_reply(stanza, "modify", "not-acceptable", "Could not parse X.509 certificate"));
			return true;
		end

		-- Check the certificate. Is it not expired? Does it include id-on-xmppAddr?

		--[[ the method expired doesn't exist in luasec .. yet?
		if cert:expired() then
			module:log("debug", "This certificate is already expired.");
			origin.send(st.error_reply(stanza, "cancel", "bad-request", "This certificate is expired."));
			return true
		end
		--]]

		if not cert:valid_at(os.time()) then
			module:log("debug", "This certificate is not valid at this moment.");
		end

		local valid_id_on_xmppAddrs;
		local require_id_on_xmppAddr = false;
		if require_id_on_xmppAddr then
			--local info = {};
			valid_id_on_xmppAddrs = {};
			for _,v in ipairs(cert:subject()) do
				--info[#info+1] = (v.name or v.oid) ..":" .. v.value;
				if v.oid == id_on_xmppAddr then
					if jid_bare(v.value) == jid_bare(origin.full_jid) then
						module:log("debug", "The certificate contains a id-on-xmppAddr key, and it is valid.");
						valid_id_on_xmppAddrs[#valid_id_on_xmppAddrs+1] = v.value;
						-- Is there a point in having >1 ids? Reject?!
					else
						module:log("debug", "The certificate contains a id-on-xmppAddr key, but it is for %s.", v.value);
						-- Reject?
					end
				end
			end

			if #valid_id_on_xmppAddrs == 0 then
				origin.send(st.error_reply(stanza, "cancel", "bad-request", "This certificate is has no valid id-on-xmppAddr field."));
				return true -- REJECT?!
			end
		end

		enable_cert(origin.username, cert, {
			id = id,
			name = name,
			x509cert = x509cert,
			no_cert_management = can_manage,
			jids = valid_id_on_xmppAddrs,
		});

		module:log("debug", "%s added certificate named %s", origin.full_jid, name);

		origin.send(st.reply(stanza));

		return true
	end
end);


local function handle_disable(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type == "set" then
		local disable = stanza.tags[1];
		module:log("debug", "%s disabled a certificate", origin.full_jid);

		local item = disable:get_child("item");
		local name = item and item.attr.id;

		if not name then
			origin.send(st.error_reply(stanza, "cancel", "bad-request", "No key specified."));
			return true
		end

		local disabled_cert = disable_cert(origin.username, name):pem();

		if disable.name == "revoke" then
			module:log("debug", "%s revoked a certificate! Disconnecting all clients that used it", origin.full_jid);
			local sessions = hosts[module.host].sessions[origin.username].sessions;

			for _, session in pairs(sessions) do
				local cert = session.external_auth_cert;
				
				if cert and cert == disabled_cert then
					module:log("debug", "Found a session that should be closed: %s", tostring(session));
					session:close{ condition = "not-authorized", text = "This client side certificate has been revoked."};
				end
			end
		end
		origin.send(st.reply(stanza));

		return true
	end
end

module:hook("iq/self/"..xmlns_saslcert..":disable", handle_disable);
module:hook("iq/self/"..xmlns_saslcert..":revoke", handle_disable);

-- Here comes the SASL EXTERNAL stuff

local now = os.time;
module:hook("stream-features", function(event)
	local session, features = event.origin, event.features;
	if session.secure and session.type == "c2s_unauthed" then
		local cert = session.conn:socket():getpeercertificate();
		if not cert then
			module:log("error", "No Client Certificate");
			return
		end
		module:log("info", "Client Certificate: %s", cert:digest(digest_algo));
		local all_certs = dm_load(nil, module.host, dm_table) or {};
		local digest = cert:digest(digest_algo);
		local username = all_certs[digest];
		if not cert:valid_at(now()) then
			module:log("debug", "Client has an expired certificate", cert:digest(digest_algo));
			return
		end
		if username then
			local certs = dm_load(username, module.host, dm_table) or {};
			local pem = cert:pem();
			for name,info in pairs(certs) do
				if info.digest == digest and info.pem == pem then
					session.external_auth_cert, session.external_auth_user = pem, username;
					module:log("debug", "Stream features:\n%s", tostring(features));
					local mechs = features:get_child("mechanisms", "urn:ietf:params:xml:ns:xmpp-sasl");
					if mechs then
						mechs:tag("mechanism"):text("EXTERNAL");
					end
				end
			end
		end
	end
end, -1);

local sm_make_authenticated = require "core.sessionmanager".make_authenticated;

module:hook("stanza/urn:ietf:params:xml:ns:xmpp-sasl:auth", function(event)
	local session, stanza = event.origin, event.stanza;
	if session.type == "c2s_unauthed" and event.stanza.attr.mechanism == "EXTERNAL" then
		if session.secure then
			local cert = session.conn:socket():getpeercertificate();
			if cert:pem() == session.external_auth_cert then
				sm_make_authenticated(session, session.external_auth_user);
				module:fire_event("authentication-success", { session = session });
				session.external_auth, session.external_auth_user = nil, nil;
				session.send(st.stanza("success", { xmlns="urn:ietf:params:xml:ns:xmpp-sasl"}));
				session:reset_stream();
			else
				module:fire_event("authentication-failure", { session = session, condition = "not-authorized" });
				session.send(st.stanza("failure", { xmlns="urn:ietf:params:xml:ns:xmpp-sasl"}):tag"not-authorized");
			end
		else
			session.send(st.stanza("failure", { xmlns="urn:ietf:params:xml:ns:xmpp-sasl"}):tag"encryption-required");
		end
		return true;
	end
end, 1);

