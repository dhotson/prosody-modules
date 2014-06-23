-- mod_profile

local st = require"util.stanza";
local jid_split, jid_bare = import("util.jid", "split", "bare");
local is_admin = require"core.usermanager".is_admin;
local vcard = require"util.vcard";
local base64 = require"util.encodings".base64;
local sha1 = require"util.hashes".sha1;

local pep_plus;
if module:get_host_type() == "local" and module:get_option_boolean("vcard_to_pep", true) then
	pep_plus = module:depends"pep_plus";
end

local loaded_pep_for = module:shared"loaded-pep-for";
local storage = module:open_store();
local legacy_storage = module:open_store("vcard");

local function get_item(vcard, name)
	local item;
	for i=1, #vcard do
		item=vcard[i];
		if item.name == name then
			return item, i;
		end
	end
end

local magic_mime = {
	["\137PNG\r\n\026\n"] = "image/png";
	["\255\216"] = "image/jpeg";
	["GIF87a"] = "image/gif";
	["GIF89a"] = "image/gif";
	["<?xml"] = "image/svg+xml";
}
local function identify(data)
	for magic, mime in pairs(magic_mime) do
		if data:sub(1, #magic) == magic then
			return mime;
		end
	end
	return "application/octet-stream";
end

local function update_pep(username, data)
	local pep = pep_plus.get_pep_service(username.."@"..module.host);
	if vcard.to_vcard4 then
		pep:purge("urn:xmpp:vcard4", true);
		pep:publish("urn:xmpp:vcard4", true, "current", st.stanza("item", {id="current"})
			:add_child(vcard.to_vcard4(data)));
	end

	local nickname = get_item(data, "NICKNAME");
	if nickname and nickname[1] then
		pep:purge("http://jabber.org/protocol/nick", true);
		pep:publish("http://jabber.org/protocol/nick", true, "current", st.stanza("item", {id="current"})
			:tag("nick", { xmlns="http://jabber.org/protocol/nick" }):text(nickname[1]));
	end

	local photo = get_item(data, "PHOTO");
	if photo and photo[1] then
		local photo_raw = base64.decode(photo[1]);
		local photo_hash = sha1(photo_raw, true);

		pep:purge("urn:xmpp:avatar:metadata", true);
		pep:purge("urn:xmpp:avatar:data", true);
		pep:publish("urn:xmpp:avatar:metadata", true, "current", st.stanza("item", {id="current"})
			:tag("metadata", {
				xmlns="urn:xmpp:avatar:metadata",
				bytes = tostring(#photo_raw),
				id = photo_hash,
				type = identify(photo_raw),
			}));
		pep:publish("urn:xmpp:avatar:data", true, photo_hash, st.stanza("item", {id="current"})
			:tag("data", { xmlns="urn:xmpp:avatar:data" }):text(photo[1]));
	end
end

-- The "temporary" vCard XEP-0054 part
module:add_feature("vcard-temp");

local function handle_get(event)
	local origin, stanza = event.origin, event.stanza;
	local username = origin.username;
	local to = stanza.attr.to;
	if to then username = jid_split(to); end
	local data = storage:get(username);
	if not data then
		data = legacy_storage:get(username);
		data = data and st.deserialize(data);
		if data then
			return origin.send(st.reply(stanza):add_child(data));
		end
	end
	if not data then
		return origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
	end
	return origin.send(st.reply(stanza):add_child(vcard.to_xep54(data)));
end

local function handle_set(event)
	local origin, stanza = event.origin, event.stanza;
	local data = vcard.from_xep54(stanza.tags[1]);
	local username = origin.username;
	local to = stanza.attr.to;
	if to then
		if not is_admin(jid_bare(stanza.attr.from), module.host) then
			return origin.send(st.error_reply(stanza, "auth", "forbidden"));
		end
		username = jid_split(to);
	end
	local ok, err = storage:set(username, data);
	if not ok then
		return origin.send(st.error_reply(stanza, "cancel", "internal-server-error", err));
	end

	if pep_plus and username then
		update_pep(username, data);
		loaded_pep_for[username] = true;
	end

	return origin.send(st.reply(stanza));
end

module:hook("iq-get/bare/vcard-temp:vCard", handle_get);
module:hook("iq-get/host/vcard-temp:vCard", handle_get);

module:hook("iq-set/bare/vcard-temp:vCard", handle_set);
module:hook("iq-set/host/vcard-temp:vCard", handle_set);

module:hook("presence/initial", function (event)
	local username = event.origin.username
	if not loaded_pep_for[username] then
		data = storage:get(username);
		if data then
			update_pep(username, data);
		end
		loaded_pep_for[username] = true;
	end
end);

-- The vCard4 part
if vcard.to_vcard4 then
	module:add_feature("urn:ietf:params:xml:ns:vcard-4.0");

	module:hook("iq-get/bare/urn:ietf:params:xml:ns:vcard-4.0:vcard", function(event)
		local origin, stanza = event.origin, event.stanza;
		local username = jid_split(stanza.attr.to) or origin.username;
		local data = storage:get(username);
		if not data then
			return origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
		end
		return origin.send(st.reply(stanza):add_child(vcard.to_vcard4(data)));
	end);

	if vcard.from_vcard4 then
		module:hook("iq-set/self/urn:ietf:params:xml:ns:vcard-4.0:vcard", function(event)
			local origin, stanza = event.origin, event.stanza;
			local ok, err = storage:set(origin.username, vcard.from_vcard4(stanza.tags[1]));
			if not ok then
				return origin.send(st.error_reply(stanza, "cancel", "internal-server-error", err));
			end
			return origin.send(st.reply(stanza));
		end);
	else
		module:hook("iq-set/self/urn:ietf:params:xml:ns:vcard-4.0:vcard", function(event)
			local origin, stanza = event.origin, event.stanza;
			return origin.send(st.error_reply(stanza, "cancel", "feature-not-implemented"));
		end);
	end
end

