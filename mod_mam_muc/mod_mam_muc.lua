-- XEP-0313: Message Archive Management for Prosody
-- Copyright (C) 2011-2012 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local xmlns_mam     = "urn:xmpp:mam:tmp";
local xmlns_delay   = "urn:xmpp:delay";
local xmlns_forward = "urn:xmpp:forward:0";

local st = require "util.stanza";
local rsm = module:require "mod_mam/rsm";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local jid_prep = require "util.jid".prep;
local host = module.host;

local dm_list_load = require "util.datamanager".list_load;
local dm_list_append = require "util.datamanager".list_append;

local tostring = tostring;
local time_now = os.time;
local m_min = math.min;
local timestamp, timestamp_parse = require "util.datetime".datetime, require "util.datetime".parse;
local uuid = require "util.uuid".generate;
local default_max_items, max_max_items = 20, module:get_option_number("max_archive_query_results", 50);
--local rooms_to_archive = module:get_option_set("rooms_to_archive",{});
-- TODO Should be possible to enforce it too

local rooms = hosts[module.host].modules.muc.rooms;
local archive_store = "archive2";

-- Handle archive queries
module:hook("iq-get/bare/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local room = jid_split(stanza.attr.to);
	local query = stanza.tags[1];

	local room_obj = rooms[room];
	if not room_obj then
		return -- FIXME not found
	end
	local from = jid_bare(stanza.attr.from);

	-- Banned or not a member of a members-only room?
	if room_obj._affiliations[from] == "outcast"
		or room_obj._data.members_only and not room_obj._affiliations[from] then
		return origin.send(st.error_reply(stanza, "auth", "forbidden"))
	end

	local qid = query.attr.queryid;

	-- Search query parameters
	local qwith = query:get_child_text("with");
	local qstart = query:get_child_text("start");
	local qend = query:get_child_text("end");
	local qset = rsm.get(query);
	module:log("debug", "Archive query, id %s with %s from %s until %s)",
		tostring(qid), qwith or "anyone", qstart or "the dawn of time", qend or "now");

	if qstart or qend then -- Validate timestamps
		local vstart, vend = (qstart and timestamp_parse(qstart)), (qend and timestamp_parse(qend))
		if (qstart and not vstart) or (qend and not vend) then
			origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid timestamp"))
			return true
		end
		qstart, qend = vstart, vend;
	end

	local qres;
	if qwith then -- Validate the 'with' jid
		local pwith = qwith and jid_prep(qwith);
		if pwith and not qwith then -- it failed prepping
			origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid JID"))
			return true
		end
		local _, _, resource = jid_split(qwith);
		qwith = jid_bare(pwith);
		qres = resource;
	end

	-- Load all the data!
	local data, err = dm_list_load(room, module.host, archive_store);
	if not data then
		if (not err) then
			module:log("debug", "The archive was empty.");
			origin.send(st.reply(stanza));
		else
			origin.send(st.error_reply(stanza, "cancel", "internal-server-error", "Error loading archive: "..tostring(err)));
		end
		return true
	end

	-- RSM stuff
	local qmax = m_min(qset and qset.max or default_max_items, max_max_items);
	local qset_matches = not (qset and qset.after);
	local first, last, index;
	local n = 0;
	local start = qset and qset.index or 1;

	module:log("debug", "Loaded %d items, about to filter", #data);
	for i=start,#data do
		local item = data[i];
		local when, nick = item.when, item.resource;
		local id = item.id;
		--module:log("debug", "id is %s", id);

		-- RSM pre-send-checking
		if qset then
			if qset.before == id then
				module:log("debug", "End of matching range found");
				qset_matches = false;
				break;
			end
		end

		--module:log("debug", "message with %s at %s", with, when or "???");
		-- Apply query filter
		if (not qres or (qres == nick))
				and (not qstart or when >= qstart)
				and (not qend or when <= qend)
				and (not qset or qset_matches) then
			local fwd_st = st.message{ to = stanza.attr.from }
				:tag("result", { xmlns = xmlns_mam, queryid = qid, id = id }):up()
				:tag("forwarded", { xmlns = xmlns_forward })
					:tag("delay", { xmlns = xmlns_delay, stamp = timestamp(when) }):up();
			local orig_stanza = st.deserialize(item.stanza);
			orig_stanza.attr.xmlns = "jabber:client";
			fwd_st:add_child(orig_stanza);
			origin.send(fwd_st);
			if not first then
				index = i;
				first = id;
			end
			last = id;
			n = n + 1;
		elseif (qend and when > qend) then
			module:log("debug", "We have passed into messages more recent than requested");
			break -- We have passed into messages more recent than requested
		end

		-- RSM post-send-checking
		if qset then
			if qset.after == id then
				module:log("debug", "Start of matching range found");
				qset_matches = true;
			end
		end
		if n >= qmax then
			module:log("debug", "Max number of items matched");
			break
		end
	end
	-- That's all folks!
	module:log("debug", "Archive query %s completed", tostring(qid));

	local reply = st.reply(stanza);
	if last then
		-- This is a bit redundant, isn't it?
		reply:query(xmlns_mam):add_child(rsm.generate{first = first, last = last, count = n});
	end
	origin.send(reply);
	return true
end);

-- Handle messages
local function message_handler(event)
	local origin, stanza = event.origin, event.stanza;
	local orig_type = stanza.attr.type or "normal";
	local orig_to = stanza.attr.to;
	local orig_from = stanza.attr.from;

	-- Still needed?
	if not orig_from then
		orig_from = origin.full_jid;
	end

	-- Only store groupchat messages
	if not (orig_type == "groupchat" and (stanza:get_child("body") or stanza:get_child("subject"))) then
		return;
	end

	local room = jid_split(orig_to);
	local room_obj = hosts[host].modules.muc.rooms[orig_to]
	if not room_obj then return end

	local id = uuid();
	local when = time_now();
	local stanza = st.clone(stanza); -- Private copy
	--stanza.attr.to = nil;
	local nick = room_obj._jid_nick[orig_from];
	if not nick then return end
	stanza.attr.from = nick;
	local _, _, nick = jid_split(nick);
	-- And stash it
	local ok, err = dm_list_append(room, host, archive_store, {
		-- WARNING This format may change.
		id = id,
		when = when,
		resource = nick,
		stanza = st.preserialize(stanza)
	});
	--[[ This was dropped from the spec
	if ok then 
		stanza:tag("archived", { xmlns = xmlns_mam, by = host, id = id }):up();
	end
	--]]
end

module:hook("message/bare", message_handler, 2);

module:add_feature(xmlns_mam);
