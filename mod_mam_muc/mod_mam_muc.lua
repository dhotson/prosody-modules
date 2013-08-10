-- XEP-0313: Message Archive Management for Prosody
-- Copyright (C) 2011-2013 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local xmlns_mam     = "urn:xmpp:mam:tmp";
local xmlns_delay   = "urn:xmpp:delay";
local xmlns_forward = "urn:xmpp:forward:0";
local muc_form_config_option = "muc#roomconfig_enablelogging"

local st = require "util.stanza";
local rsm = module:require "mod_mam/rsm";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;

local getmetatable = getmetatable;
local function is_stanza(x)
	return getmetatable(x) == st.stanza_mt;
end

local tostring = tostring;
local time_now = os.time;
local m_min = math.min;
local timestamp, timestamp_parse = require "util.datetime".datetime, require "util.datetime".parse;
local default_max_items, max_max_items = 20, module:get_option_number("max_archive_query_results", 50);

local log_all_rooms = module:get_option_boolean("muc_log_all_rooms", false);
local log_by_default = module:get_option_boolean("muc_log_by_default", true);
local advertise_archive = module:get_option_boolean("muc_log_advertise", true);

local archive = module:open_store("archive2", "archive");
local rooms = hosts[module.host].modules.muc.rooms;

module:hook("muc-config-form", function(event)
	local room, form = event.room, event.form;
	table.insert(form,
	{
		name = muc_form_config_option,
		type = "boolean",
		label = "Enable Logging?",
		value = room._data.logging or false,
	}
	);
end);

module:hook("muc-config-submitted", function(event)
	local room, fields, changed = event.room, event.fields, event.changed;
	local new = fields[muc_form_config_option];
	if new ~= room._data.logging then
		room._data.logging = new;
		if type(changed) == "table" then
			changed[muc_form_config_option] = true;
		else
			event.changed = true;
		end
	end
end);


-- Handle archive queries
module:hook("iq-get/bare/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local room = stanza.attr.to;
	local query = stanza.tags[1];

	local room_obj = rooms[room];
	if not room_obj then
		return origin.send(st.error_reply(stanza, "cancel", "item-not-found"))
	end
	local from = jid_bare(stanza.attr.from);

	-- Banned or not a member of a members-only room?
	if room_obj._affiliations[from] == "outcast"
		or room_obj._data.members_only and not room_obj._affiliations[from] then
		return origin.send(st.error_reply(stanza, "auth", "forbidden"))
	end

	local qid = query.attr.queryid;

	-- Search query parameters
	local qstart = query:get_child_text("start");
	local qend = query:get_child_text("end");
	module:log("debug", "Archive query, id %s from %s until %s)",
		tostring(qid), qstart or "the dawn of time", qend or "now");

	if qstart or qend then -- Validate timestamps
		local vstart, vend = (qstart and timestamp_parse(qstart)), (qend and timestamp_parse(qend))
		if (qstart and not vstart) or (qend and not vend) then
			origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid timestamp"))
			return true
		end
		qstart, qend = vstart, vend;
	end

	-- RSM stuff
	local qset = rsm.get(query);
	local qmax = m_min(qset and qset.max or default_max_items, max_max_items);
	local reverse = qset and qset.before or false;

	local before, after = qset and qset.before, qset and qset.after;
	if type(before) ~= "string" then before = nil; end

	-- Load all the data!
	local data, err = archive:find(origin.username, {
		start = qstart; ["end"] = qend; -- Time range
		limit = qmax;
		before = before; after = after;
		reverse = reverse;
		total = true;
	});

	if not data then
		return origin.send(st.error_reply(stanza, "cancel", "internal-server-error"));
	end
	local count = err;

	-- Wrap it in stuff and deliver
	local first, last;
	for id, item, when in data do
		local fwd_st = st.message{ to = origin.full_jid }
			:tag("result", { xmlns = xmlns_mam, queryid = qid, id = id })
				:tag("forwarded", { xmlns = xmlns_forward })
					:tag("delay", { xmlns = xmlns_delay, stamp = timestamp(when) }):up();

		if not is_stanza(item) then
			item = st.deserialize(item);
		end
		item.attr.xmlns = "jabber:client";
		fwd_st:add_child(item);

		if not first then first = id; end
		last = id;

		origin.send(fwd_st);
	end
	-- That's all folks!
	module:log("debug", "Archive query %s completed", tostring(qid));

	if reverse then first, last = last, first; end
	return origin.send(st.reply(stanza)
		:query(xmlns_mam):add_child(rsm.generate {
			first = first, last = last, count = count }));
end);

-- Handle messages
local function message_handler(event)
	local stanza = event.stanza;
	local orig_type = stanza.attr.type or "normal";
	local orig_to = stanza.attr.to;
	local orig_from = stanza.attr.from;

	-- Only store groupchat messages
	if not (orig_type == "groupchat" and (stanza:get_child("body") or stanza:get_child("subject"))) then
		return;
		-- Chat states and other non-content messages, what TODO?
	end

	local room = jid_split(orig_to);
	local room_obj = rooms[orig_to]
	if not room_obj then return end -- No such room

	if not ( log_all_rooms == true -- Logging forced on all rooms
	or (room_obj._data.logging == nil and log_by_default == true)
	or room_obj._data.logging ) then return end -- Don't log

	local nick = room_obj._jid_nick[orig_from];
	if not nick then return end -- Message from someone not in the room?

	stanza.attr.from = nick;
	-- And stash it
	local ok, id = archive:append(room, time_now(), "", stanza);
	stanza.attr.from = orig_from;
	if ok and advertise_archive then
		stanza:tag("archived", { xmlns = xmlns_mam, by = jid_bare(orig_to), id = id }):up();
	end
end

module:hook("message/bare", message_handler, 2);

-- TODO should we perhaps log presence as well?
-- And role/affiliation changes?

module:add_feature(xmlns_mam);
