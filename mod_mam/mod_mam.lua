-- XEP-0313: Message Archive Management for Prosody
-- Copyright (C) 2011-2012 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local xmlns_mam     = "urn:xmpp:mam:tmp";
local xmlns_delay   = "urn:xmpp:delay";
local xmlns_forward = "urn:xmpp:forward:0";

local st = require "util.stanza";
local rsm = module:require "rsm";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local host = module.host;

local dm_load = require "util.datamanager".load;
local dm_store = require "util.datamanager".store;
local dm_list_load = require "util.datamanager".list_load;
local dm_list_append = require "util.datamanager".list_append;
local rm_load_roster = require "core.rostermanager".load_roster;

local tostring = tostring;
local time_now = os.time;
local m_min = math.min;,
local timestamp, timestamp_parse = require "util.datetime".datetime, require "util.datetime".parse;
local uuid = require "util.uuid".generate;
local default_max_items, max_max_items = 20, module:get_option_number("max_archive_query_results", 50);
local global_default_policy = module:get_option("default_archive_policy", false);
-- TODO Should be possible to enforce it too


-- For translating preference names from string to boolean and back
local default_attrs = {
	always = true, [true] = "always",
	never = false, [false] = "never",
	roster = "roster",
}

do
	local prefs_format = {
		[false] = "roster",
		-- default ::= true | false | "roster"
		-- true = always, false = never, nil = global default
		["romeo@montague.net"] = true, -- always
		["montague@montague.net"] = false, -- newer
	};
end

local archive_store = "archive2";
local prefs_store = archive_store .. "_prefs";
local function get_prefs(user)
	return dm_load(user, host, prefs_store) or
		{ [false] = global_default_policy };
end
local function set_prefs(user, prefs)
	return dm_store(user, host, prefs_store, prefs);
end


-- Handle prefs.
module:hook("iq/self/"..xmlns_mam..":prefs", function(event)
	local origin, stanza = event.origin, event.stanza;
	local user = origin.username;
	if stanza.attr.type == "get" then
		local prefs = get_prefs(user);
		local default = prefs[false];
		default = default ~= nil and default_attrs[default] or global_default_policy;
		local reply = st.reply(stanza):tag("prefs", { xmlns = xmlns_mam, default = default })
		local always = st.stanza("always");
		local never = st.stanza("never");
		for k,v in pairs(prefs) do
			if k then
				(v and always or never):tag("jid"):text(k):up();
			end
		end
		reply:add_child(always):add_child(never);
		origin.send(reply);
		return true
	else -- type == "set"
		local prefs = {};
		local new_prefs = stanza:get_child("prefs", xmlns_mam);
		local new_default = new_prefs.attr.default;
		if new_default then
			prefs[false] = default_attrs[new_default];
		end

		local always = new_prefs:get_child("always");
		if always then
			for rule in always:childtags("jid") do
				local jid = rule:get_text();
				prefs[jid] = true;
			end
		end

		local never = new_prefs:get_child("never");
		if never then
			for rule in never:childtags("jid") do
				local jid = rule:get_text();
				prefs[jid] = false;
			end
		end

		local ok, err = set_prefs(user, prefs);
		if not ok then
			origin.send(st.error_reply(stanza, "cancel", "internal-server-error", "Error storing preferences: "..tostring(err)));
		else
			origin.send(st.reply(stanza));
		end
		return true
	end
end);

-- Handle archive queries
module:hook("iq/self/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local query = stanza.tags[1];
	if stanza.attr.type == "get" then
		local qid = query.attr.queryid;

		-- Search query parameters
		local qwith = query:get_child_text("with");
		local qstart = query:get_child_text("start");
		local qend = query:get_child_text("end");
		local qset = rsm.get(query);
		module:log("debug", "Archive query, id %s with %s from %s until %s)",
			tostring(qid), qwith or "anyone", qstart or "the dawn of time", qend or "now");

		qstart, qend = (qstart and timestamp_parse(qstart)), (qend and timestamp_parse(qend))

		-- Load all the data!
		local data, err = dm_list_load(origin.username, origin.host, archive_store);
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
			local when, with, with_bare = item.when, item.with, item.with_bare;
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
			if (not qwith or ((qwith == with) or (qwith == with_bare)))
					and (not qstart or when >= qstart)
					and (not qend or when <= qend)
					and (not qset or qset_matches) then
				local fwd_st = st.message{ to = origin.full_jid }
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
				if n >= qmax then
					module:log("debug", "Max number of items matched");
					break
				end
			end
		end
		-- That's all folks!
		module:log("debug", "Archive query %s completed", tostring(qid));

		local reply = st.reply(stanza);
		if last then
			-- This is a bit redundant, isn't it?
			reply:query(xmlns_mam):add_child(rsm.generate{last = last});
		end
		origin.send(reply);
		return true
	end
end);

local function has_in_roster(user, who)
	local roster = rm_load_roster(user, host);
	module:log("debug", "%s has %s in roster? %s", user, who, roster[who] and "yes" or "no");
	return roster and roster[who];
end

local function shall_store(user, who)
	-- TODO Cache this?
	local prefs = get_prefs(user);
	local rule = prefs[who];
	module:log("debug", "%s's rule for %s is %s", user, who, tostring(rule))
	if rule ~= nil then
		return rule;
	else -- Below could be done by a metatable
		local default = prefs[false];
		module:log("debug", "%s's default rule is %s", user, tostring(default))
		if default == nil then
			default = global_default_policy;
			module:log("debug", "Using global default rule, %s", tostring(default))
		end
		if default == "roster" then
			return has_in_roster(user, who);
		end
		return default;
	end
end

-- Handle messages
local function message_handler(event, c2s)
	local origin, stanza = event.origin, event.stanza;
	local orig_type = stanza.attr.type or "normal";
	local orig_to = stanza.attr.to;
	local orig_from = stanza.attr.from;

	if not orig_from and c2s then
		orig_from = origin.full_jid;
	end
	orig_to = orig_to or orig_from; -- Weird corner cases

	-- Don't store messages of these types
	if orig_type == "error"
	or orig_type == "headline"
	or orig_type == "groupchat"
	or not stanza:get_child("body") then
		return;
		-- TODO Maybe headlines should be configurable?
		-- TODO Write a mod_mam_muc for groupchat messages.
	end

	local store_user, store_host = jid_split(c2s and orig_from or orig_to);
	local target_jid = c2s and orig_to or orig_from;
	local target_bare = jid_bare(target_jid);

	if shall_store(store_user, target_bare) then
		module:log("debug", "Archiving stanza: %s", stanza:top_tag());

		local id = uuid();
		local when = time_now();
		-- And stash it
		local ok, err = dm_list_append(store_user, store_host, archive_store, {
			-- WARNING This format may change.
			id = id,
			when = when,
			with = target_jid,
			with_bare = target_bare, -- Optimization, to avoid loads of jid_bare() calls when filtering.
			stanza = st.preserialize(stanza)
		});
		--[[ This was dropped from the spec
		if ok then 
			stanza:tag("archived", { xmlns = xmlns_mam, by = host, id = id }):up();
		end
		--]]
	else
		module:log("debug", "Not archiving stanza: %s", stanza:top_tag());
	end
end

local function c2s_message_handler(event)
	return message_handler(event, true);
end

-- Stanzas sent by local clients
module:hook("pre-message/bare", c2s_message_handler, 2);
module:hook("pre-message/full", c2s_message_handler, 2);
-- Stanszas to local clients
module:hook("message/bare", message_handler, 2);
module:hook("message/full", message_handler, 2);

module:add_feature(xmlns_mam);

