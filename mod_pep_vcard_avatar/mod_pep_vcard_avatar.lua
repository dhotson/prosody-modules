-- Prosody IM
-- Copyright (C) 2008-2014 Matthew Wild
-- Copyright (C) 2008-2014 Waqas Hussain
-- Copyright (C) 2014 Kim Alvefur
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza"
local base64 = require"util.encodings".base64;
local sha1 = require"util.hashes".sha1;

local mod_pep = module:depends"pep";
local pep_data = mod_pep.module.save().data;

module:add_feature("http://prosody.im/protocol/vcard-pep-integration");
module:depends"vcard";
local vcard_storage = module:open_store("vcard");

local function get_vcard(username)
	local vcard, err = vcard_storage:get(username);
	if vcard then
		vcard = st.deserialize(vcard);
	end
	if not vcard then
		vcard = st.stanza("vCard", { xmlns = "vcard-temp" });
	end
	return vcard, err;
end

local function set_vcard(username, vcard)
	if vcard then
		vcard = st.preserialize(st.clone(vcard));
	end
	return vcard_storage:set(username, vcard);
end

local function publish(session, node, id, item)
	return module:fire_event("pep-publish-item", {
		actor = true, session = session, node = node, id = id, item = item;
	});
end

-- vCard -> PEP
local function update_pep(session, vcard)
	local nickname = vcard and vcard:get_child_text("NICKNAME");
	if nickname then
		publish(session, "http://jabber.org/protocol/nick", "current", st.stanza("item", {id="current"})
			:tag("nick", { xmlns="http://jabber.org/protocol/nick" }):text(nickname));
	end

	local photo = vcard and vcard:get_child("PHOTO");
	if photo then
		local photo_type = photo:get_child_text("TYPE");
		local photo_b64 = photo:get_child_text("BINVAL");
		local photo_raw = photo_b64 and base64.decode(photo_b64);
		if photo_raw and photo_type then -- Else invalid data or encoding
			local photo_hash = sha1(photo_raw, true);

			publish(session, "urn:xmpp:avatar:data", photo_hash, st.stanza("item", {id=photo_hash})
				:tag("data", { xmlns="urn:xmpp:avatar:data" }):text(photo_b64));
			publish(session, "urn:xmpp:avatar:metadata", photo_hash, st.stanza("item", {id=photo_hash})
				:tag("metadata", { xmlns="urn:xmpp:avatar:metadata" })
					:tag("info", { id = photo_hash, bytes = tostring(#photo_raw), type = photo_type,}));
		end
	end
end

local function handle_vcard(event)
	local session, stanza = event.origin, event.stanza;
	if not stanza.attr.to and stanza.attr.type == "set" then
		return update_pep(session, stanza:get_child("vCard", "vcard-temp"));
	end
end

module:hook("iq/bare/vcard-temp:vCard", handle_vcard, 1);

-- PEP Avatar -> vCard
local function on_publish_metadata(event)
	local username = event.session.username;
	local metadata = event.item:find("{urn:xmpp:avatar:metadata}metadata/info");
	if not metadata then
		module:log("error", "No info found");
		module:log("debug", event.item:top_tag());
		return;
	end
	module:log("debug", metadata:top_tag());
	local user_data = pep_data[username.."@"..module.host];
	local pep_photo = user_data["urn:xmpp:avatar:data"];
	pep_photo = pep_photo and pep_photo[1] == metadata.attr.id and pep_photo[2];
	if not pep_photo then
		module:log("error", "No photo found");
		return;
	end -- Publishing in the wrong order?
	local vcard = get_vcard(username);
	local old_photo = vcard:get_child("PHOTO");
	if old_photo then
		local photo_type = old_photo:get_child("TYPE");
		photo_type[1] = metadata.attr.type;
		local photo_b64 = old_photo:get_child("BINVAL");
		photo_b64[1] = pep_photo:get_child_text("data", "urn:xmpp:avatar:data");
	end
	set_vcard(username, vcard);
end

-- PEP Nickname -> vCard
local function on_publish_nick(event)
	local username = event.session.username;
	local vcard = get_vcard(username);
	local new_nick = event.item:get_child_text("nick", "http://jabber.org/protocol/nick");
	local old_nick = vcard:get_child("NICKNAME");
	if not old_nick then
		vcard:tag("NICKNAME"):text(new_nick);
	elseif old_nick[1] ~= new_nick then
		old_nick[1] = new_nick;
	else
		return -- no change
	end
	set_vcard(username, vcard);
end

local function on_publish(event)
	if event.actor == true then return end -- Not from a client
	local node = event.node;
	if node == "urn:xmpp:avatar:metadata" then
		return on_publish_metadata(event);
	elseif node == "http://jabber.org/protocol/nick" then
		return on_publish_nick(event);
	end
end

module:hook("pep-publish-item", on_publish, 1);
