-- XEP-0313: Message Archive Management for Prosody MUC
-- Copyright (C) 2011-2014 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local xmlns_mam     = "urn:xmpp:mam:0";
local xmlns_delay   = "urn:xmpp:delay";
local xmlns_forward = "urn:xmpp:forward:0";
local muc_form_enable_logging = "muc#roomconfig_enablelogging"

local st = require "util.stanza";
local rsm = module:require "mod_mam/rsm";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local dataform = require "util.dataforms".new;

local mod_muc = module:depends"muc";
local room_mt = mod_muc.room_mt;
local rooms = mod_muc.rooms;

local getmetatable = getmetatable;
local function is_stanza(x)
	return getmetatable(x) == st.stanza_mt;
end

local tostring = tostring;
local time_now = os.time;
local m_min = math.min;
local timestamp, timestamp_parse = require "util.datetime".datetime, require "util.datetime".parse;
local max_history_length = module:get_option_number("max_history_messages", 1000);
local default_max_items, max_max_items = 20, module:get_option_number("max_archive_query_results", max_history_length);

local log_all_rooms = module:get_option_boolean("muc_log_all_rooms", false);
local log_by_default = module:get_option_boolean("muc_log_by_default", true);

local archive_store = "archive2";
local archive = module:open_store(archive_store, "archive");
if not archive or archive.name == "null" then
        module:log("error", "Could not open archive storage");
        return
elseif not archive.find then
        module:log("error", "mod_%s does not support archiving, switch to mod_storage_sql2", archive._provided_by);
        return
end

local send_history, save_to_history;

	-- Override history methods for all rooms.
module:hook("muc-room-created", function (event)
	local room = event.room;
	if log_all_rooms or room._data.logging then
		room.send_history = send_history;
		room.save_to_history = save_to_history;
	end
end);

function module.load()
	for _, room in pairs(rooms) do
		if log_all_rooms or room._data.logging then
			room.send_history = send_history;
			room.save_to_history = save_to_history;
		end
	end
end
function module.unload()
	for _, room in pairs(rooms) do
		if room.send_history == send_history then
			room.send_history = nil;
			room.save_to_history = nil;
		end
	end
end

if not log_all_rooms then
	module:hook("muc-config-form", function(event)
		local room, form = event.room, event.form;
		local logging_enabled = room._data.logging;
		if logging_enabled == nil then
			logging_enabled = log_by_default;
		end
		table.insert(form,
		{
			name = muc_form_enable_logging,
			type = "boolean",
			label = "Enable Logging?",
			value = logging_enabled,
		}
		);
	end);

	module:hook("muc-config-submitted", function(event)
		local room, fields, changed = event.room, event.fields, event.changed;
		local new = fields[muc_form_enable_logging];
		if new ~= room._data.logging then
			room._data.logging = new;
			if type(changed) == "table" then
				changed[muc_form_enable_logging] = true;
			else
				event.changed = true;
			end
			if new then
				room.send_history = send_history;
				room.save_to_history = save_to_history;
			else
				room.send_history = nil;
				room.save_to_history = nil;
			end
		end
	end);
end

local query_form = dataform {
	{ name = "FORM_TYPE"; type = "hidden"; value = xmlns_mam; };
	{ name = "with"; type = "jid-single"; };
	{ name = "start"; type = "text-single" };
	{ name = "end"; type = "text-single"; };
};

-- Serve form
module:hook("iq-get/self/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	return origin.send(st.reply(stanza):add_child(query_form:form()));
end);

-- Handle archive queries
module:hook("iq-set/bare/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local room = stanza.attr.to;
	local room_node = jid_split(room);
	local orig_from = stanza.attr.from;
	local query = stanza.tags[1];

	local room_obj = rooms[room];
	if not room_obj then
		return origin.send(st.error_reply(stanza, "cancel", "item-not-found"))
	end
	local from = jid_bare(orig_from);

	-- Banned or not a member of a members-only room?
	local from_affiliation = room_obj:get_affiliation(from);
	if from_affiliation == "outcast" -- banned
		or room_obj:get_members_only() and not from_affiliation then -- members-only, not a member
		return origin.send(st.error_reply(stanza, "auth", "forbidden"))
	end

	local qid = query.attr.queryid;

	-- Search query parameters
	local qwith, qstart, qend;
	local form = query:get_child("x", "jabber:x:data");
	if form then
		local err;
		form, err = query_form:data(form);
		if err then
			return origin.send(st.error_reply(stanza, "modify", "bad-request", select(2, next(err))))
		end
		qwith, qstart, qend = form["with"], form["start"], form["end"];
		qwith = qwith and jid_bare(qwith); -- dataforms does jidprep
	end

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
	local data, err = archive:find(room_node, {
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

	origin.send(st.reply(stanza))
	local msg_reply_attr = { to = stanza.attr.from, from = stanza.attr.to };

	-- Wrap it in stuff and deliver
	local fwd_st, first, last;
	for id, item, when in data do
		fwd_st = st.message(msg_reply_attr)
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
	return origin.send(st.message(msg_reply_attr)
		:tag("fin", { xmlns = xmlns_mam, queryid = qid })
			:add_child(rsm.generate {
				first = first, last = last, count = count }));
end);

function send_history(self, to, stanza)
	local maxchars, maxstanzas, seconds, since;
	local history_tag = stanza:find("{http://jabber.org/protocol/muc}x/history")
	if history_tag then
		module:log("debug", tostring(history_tag));
		local history_attr = history_tag.attr;
		maxchars = tonumber(history_attr.maxchars);
		maxstanzas = tonumber(history_attr.maxstanzas);
		seconds = tonumber(history_attr.seconds);
		since = history_attr.since;
		if since then
			since = timestamp_parse(since);
		end
		if seconds then
			since = math.max(os.time() - seconds, since or 0);
		end
	end

	-- Load all the data!
	local data, err = archive:find(jid_split(self.jid), {
		limit = m_min(maxstanzas or 20, max_history_length);
		start = since;
		reverse = true;
		with = "message<groupchat";
	});

	if not data then
		module:log("error", "Could not fetch history: %s", tostring(err));
		return
	end

	local to_send = {};
	local charcount = 0;
	local chars;
	for id, item, when in data do
		item.attr.to = to;
		item:tag("delay", { xmlns = "urn:xmpp:delay", from = self.jid, stamp = timestamp(when) }):up(); -- XEP-0203
		if maxchars then
			chars = #tostring(item);
			if chars + charcount > maxchars then break end
			charcount = charcount + chars;
		end
		to_send[1+#to_send] = item;
	end
	for i = #to_send,1,-1 do
		self:_route_stanza(to_send[i]);
	end
end

-- Handle messages
function save_to_history(self, stanza)
	local orig_to = stanza.attr.to;
	local room = jid_split(self.jid);

	-- Policy check
	if not ( log_all_rooms == true -- Logging forced on all rooms
	or (self._data.logging == nil and log_by_default == true)
	or self._data.logging ) then return end -- Don't log

	module:log("debug", "We're logging this")
	-- And stash it
	local with = stanza.name
	if stanza.attr.type then
		with = with .. "<" .. stanza.attr.type
	end
	archive:append(room, nil, time_now(), with, stanza);
end

module:hook("muc-room-destroyed", function(event)
	archive:delete(jid_split(event.room.jid));
end);

-- TODO should we perhaps log presence as well?
-- And role/affiliation changes?

module:add_feature(xmlns_mam);
