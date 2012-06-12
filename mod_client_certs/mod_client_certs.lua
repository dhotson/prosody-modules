-- XEP-0257: Client Certificates Management implementation for Prosody
-- Copyright (C) 2012 Thijs Alkemade
--
-- This file is MIT/X11 licensed.

local st = require "util.stanza";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local xmlns_saslcert = "urn:xmpp:saslcert:0";
local xmlns_pubkey = "urn:xmpp:tmp:pubkey";
local dm_load = require "util.datamanager".load;
local dm_store = require "util.datamanager".store;
local dm_table = "client_certs";
local x509 = require "ssl.x509";
local id_on_xmppAddr = "1.3.6.1.5.5.7.8.5";
local id_ce_subjectAltName = "2.5.29.17";
local digest_algo = "sha1";
local base64 = require "util.encodings".base64;

local function enable_cert(username, cert, info)
	local certs = dm_load(username, module.host, dm_table) or {};

	info.pem = cert:pem();
	local digest = cert:digest(digest_algo);
	info.digest = digest;
	certs[info.id] = info;

	dm_store(username, module.host, dm_table, certs);
	return true
end

local function disable_cert(username, name)
	local certs = dm_load(username, module.host, dm_table) or {};

	local info = certs[name];
	local cert;
	if info then
		certs[name] = nil;
		cert = x509.cert_from_pem(info.pem);
	else
		return nil, "item-not-found"
	end

	dm_store(username, module.host, dm_table, certs);
	return cert; -- So we can compare it with stuff
end

local function get_id_on_xmpp_addrs(cert)
	local id_on_xmppAddrs = {};
	for k,ext in pairs(cert:extensions()) do
		if k == id_ce_subjectAltName then
			for e,extv in pairs(ext) do
				if e == id_on_xmppAddr then
					for i,v in ipairs(extv) do
						id_on_xmppAddrs[#id_on_xmppAddrs+1] = v;
					end
				end
			end
		end
	end
	module:log("debug", "Found JIDs: (%d) %s", #id_on_xmppAddrs, table.concat(id_on_xmppAddrs, ", "));
	return id_on_xmppAddrs;
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
		local x509cert = key_info:get_child_text("x509cert"):gsub("^%s*(.-)%s*$", "%1");

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
		local require_id_on_xmppAddr = true;
		if require_id_on_xmppAddr then
			valid_id_on_xmppAddrs = get_id_on_xmpp_addrs(cert);

			local found = false;
			for i,k in pairs(valid_id_on_xmppAddrs) do
				if jid_bare(k) == jid_bare(origin.full_jid) then
					found = true;
					break;
				end
			end

			if not found then
				origin.send(st.error_reply(stanza, "cancel", "bad-request", "This certificate is has no valid id-on-xmppAddr field."));
				return true -- REJECT?!
			end
		end

		enable_cert(origin.username, cert, {
			id = id,
			name = name,
			x509cert = x509cert,
			no_cert_management = can_manage,
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

		local disabled_cert = disable_cert(origin.username, name);

		if disabled_cert and disable.name == "revoke" then
			module:log("debug", "%s revoked a certificate! Disconnecting all clients that used it", origin.full_jid);
			local sessions = hosts[module.host].sessions[origin.username].sessions;
			local disabled_cert_pem = disabled_cert:pem();

			for _, session in pairs(sessions) do
				if session and session.conn then
					local cert = session.conn:socket():getpeercertificate();
				
					if cert and cert:pem() == disabled_cert_pem then
						module:log("debug", "Found a session that should be closed: %s", tostring(session));
						session:close{ condition = "not-authorized", text = "This client side certificate has been revoked."};
					end
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
		if not cert:valid_at(now()) then
			module:log("debug", "Client has an expired certificate", cert:digest(digest_algo));
			return
		end
		module:log("debug", "Stream features:\n%s", tostring(features));
		local mechs = features:get_child("mechanisms", "urn:ietf:params:xml:ns:xmpp-sasl");
		if mechs then
			mechs:tag("mechanism"):text("EXTERNAL");
		end
	end
end, -1);

local sm_make_authenticated = require "core.sessionmanager".make_authenticated;

module:hook("stanza/urn:ietf:params:xml:ns:xmpp-sasl:auth", function(event)
	local session, stanza = event.origin, event.stanza;
	if session.type == "c2s_unauthed" and stanza.attr.mechanism == "EXTERNAL" then
		if session.secure then
			local cert = session.conn:socket():getpeercertificate();
			local username_data = stanza:get_text();
			local username = nil;

			if username_data == "=" then
				-- Check for either an id_on_xmppAddr
				local jids = get_id_on_xmpp_addrs(cert);

				if not (#jids == 1) then
					module:log("debug", "Client tried to authenticate as =, but certificate has multiple JIDs.");
					module:fire_event("authentication-failure", { session = session, condition = "not-authorized" });
					session.send(st.stanza("failure", { xmlns="urn:ietf:params:xml:ns:xmpp-sasl"}):tag"not-authorized");
					return true;
				end

				username = jids[1];
			else
				-- Check the base64 encoded username
				username = base64.decode(username_data);
			end

			local user, host, resource = jid_split(username);

			module:log("debug", "Inferred username: %s", user or "nil");

			if (not username) or (not host == module.host) then
				module:log("debug", "No valid username found for %s", tostring(session));
				module:fire_event("authentication-failure", { session = session, condition = "not-authorized" });
				session.send(st.stanza("failure", { xmlns="urn:ietf:params:xml:ns:xmpp-sasl"}):tag"not-authorized");
				return true;
			end

			local certs = dm_load(user, module.host, dm_table) or {};
			local digest = cert:digest(digest_algo);
			local pem = cert:pem();

			for name,info in pairs(certs) do
				if info.digest == digest and info.pem == pem then
					sm_make_authenticated(session, user);
					module:fire_event("authentication-success", { session = session });
					session.send(st.stanza("success", { xmlns="urn:ietf:params:xml:ns:xmpp-sasl"}));
					session:reset_stream();
					return true;
				end
			end
			module:fire_event("authentication-failure", { session = session, condition = "not-authorized" });
			session.send(st.stanza("failure", { xmlns="urn:ietf:params:xml:ns:xmpp-sasl"}):tag"not-authorized");
		else
			session.send(st.stanza("failure", { xmlns="urn:ietf:params:xml:ns:xmpp-sasl"}):tag"encryption-required");
		end
		return true;
	end
end, 1);

