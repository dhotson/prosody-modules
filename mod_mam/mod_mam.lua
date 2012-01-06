-- XEP-xxxx: Message Archive Management for Prosody
-- Copyright (C) 2011-2012 Kim Alvefur
--
-- This file is MIT/X11 licensed.
--
-- Based on MAM ProtoXEP Version 0.1 (2010-07-01)

local st = require "util.stanza";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local xmlns_mam     = "urn:xmpp:mam:tmp";
local xmlns_delay   = "urn:xmpp:delay";
local xmlns_forward = "urn:xmpp:forward:0";
local host_sessions = hosts[module.host].sessions;
local dm_list_load = require "util.datamanager".list_load
local dm_list_append = require "util.datamanager".list_append
local time_now = os.time;
local timestamp, timestamp_parse = require "util.datetime".datetime, require "util.datetime".parse;
local uuid = require "util.uuid".generate;

-- TODO This, and appropritate filtering in message_handler()
module:hook("iq/self/"..xmlns_mam..":prefs", function(event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type == "get" then
		-- Not implemented yet, hardcoded to store everything.
		origin.send(st.reply(stanza)
			:tag("prefs", { xmlns = xmlns_mam, default = "always" }));
		return true
	else -- type == "set"
		-- TODO
	end
end);

module:hook("iq/self/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local query = stanza.tags[1];
	if stanza.attr.type == "get" then
		local qid = query.attr.queryid;

		-- Search query parameters
		local qwith = query:get_child_text("with");
		local qstart = query:get_child_text("start");
		local qend = query:get_child_text("end");
		module:log("debug", "Archive query, id %s with %s from %s until %s)",
			tostring(qid), qwith or "anyone", qstart or "the dawn of time", qend or "now");
		
		local qwith = qwith and jid_bare(qwith); -- FIXME Later, full vs bare query.
		qstart, qend = (qstart and timestamp_parse(qstart)), (qend and timestamp_parse(qend))

		-- Load all the data!
		local data, err = dm_list_load(origin.username, origin.host, "archive2"); --FIXME Decide storage name. achive2, [sm]am, archive_ng, for_fra_and_nsa
		module:log("debug", "Loaded %d items, about to filter", #(data or {}));
		for i=1,#data do
			local item = data[i];
			local when, with = item.when, item.with_bare;
			local ts = item.timestamp;
			-- FIXME Premature optimization: Bare JIDs only
			--module:log("debug", "message with %s when %s", with, when or "???");
			-- Apply query filter
			if (not qwith or qwith == with)
					and (not qstart or when >= qstart)
					and (not qend or when <= qend) then
				-- Optimizable? Do this when archiving?
				--module:log("debug", "sending");
				local fwd_st = st.message{ to = origin.full_jid }
					:tag("result", { xmlns = xmlns_mam, queryid = qid }):up()
					:tag("forwarded", { xmlns = xmlns_forward })
						:tag("delay", { xmlns = xmlns_delay, stamp = ts or timestamp(when) }):up();
				local orig_stanza = st.deserialize(item.stanza);
				orig_stanza.attr.xmlns = "jabber:client";
				fwd_st:add_child(orig_stanza);
				origin.send(fwd_st);
			end
		end
		-- That's all folks!
		module:log("debug", "Archive query %s completed", tostring(qid));
		origin.send(st.reply(stanza));
		return true
	end
end);

local function message_handler(event, c2s)
	local origin, stanza = event.origin, event.stanza;
	local orig_type = stanza.attr.type or "normal";
	local orig_to = stanza.attr.to;
	local orig_from = stanza.attr.from;

	if not orig_from and c2s then
		orig_from = origin.full_jid;
	end

	-- Don't store messages of these types
	if orig_type == "error"
	or orig_type == "headline"
	or orig_type == "groupchat" then
		return;
		-- TODO Maybe headlines should be configurable?
		-- TODO Write a mod_mam_muc for groupchat messages.
	end

	-- Stamp "We archived this" on the message
	stanza:tag("archived", { xmlns = xmlns_mam, by = module.host, id = uuid() });
	local store_user, store_host = jid_split(c2s and orig_from or orig_to);

	local when = time_now();
	-- And stash it
	dm_list_append(store_user, store_host, "archive2", {
		when = when, -- This might be an UNIX timestamp. Probably.
		timestamp = timestamp(when), -- Textual timestamp. But I'll assume that comparing numbers is faster and less annoying in case of timezones.
		with = c2s and orig_to or orig_from,
		with_bare = jid_bare(c2s and orig_to or orig_from), -- Premature optimization, to avoid loads of jid_bare() calls when filtering.
		stanza = st.preserialize(stanza)
	});
end

local function c2s_message_handler(event)
	return message_handler(event, true);
end

-- Stanzas sent by local clients
module:hook("pre-message/bare", c2s_message_handler, 1);
module:hook("pre-message/full", c2s_message_handler, 1);
-- Stanszas to local clients
module:hook("message/bare", message_handler, 1);
module:hook("message/full", message_handler, 1);

module:add_feature(xmlns_mam);
