--
-- mod_remote_roster
--
-- This is an experimental implementation of http://jkaluza.fedorapeople.org/remote-roster.html
--

local st = require "util.stanza";
local jid_split = require "util.jid".split;
local jid_prep = require "util.jid".prep;
local t_concat = table.concat;
local tonumber = tonumber;
local pairs, ipairs = pairs, ipairs;
local hosts = hosts;

local load_roster = require "core.rostermanager".load_roster;
local rm_remove_from_roster = require "core.rostermanager".remove_from_roster;
local rm_add_to_roster = require "core.rostermanager".add_to_roster;
local rm_roster_push = require "core.rostermanager".roster_push;
local core_post_stanza = core_post_stanza;
local user_exists = require "core.usermanager".user_exists;
local add_task = require "util.timer".add_task;

module:hook("iq-get/bare/jabber:iq:roster:query", function(event)
	local origin, stanza = event.origin, event.stanza;
	
	if origin.type == "component" and stanza.attr.from == origin.host then
		local node, host = jid_split(stanza.attr.to);
		local roster = load_roster(node, host);
		
		local reply = st.reply(stanza):query("jabber:iq:roster");
		for jid, item in pairs(roster) do
			if jid ~= "pending" and jid then
				local node, host = jid_split(jid);
				if host == origin.host then -- only include contacts which are on this component
					reply:tag("item", {
						jid = jid,
						subscription = item.subscription,
						ask = item.ask,
						name = item.name,
					});
					for group in pairs(item.groups) do
						reply:tag("group"):text(group):up();
					end
					reply:up(); -- move out from item
				end
			end
		end
		origin.send(reply);
		--origin.interested = true; -- resource is interested in roster updates
		return true;
	end
end);

module:hook("iq-set/bare/jabber:iq:roster:query", function(event)
	local session, stanza = event.origin, event.stanza;
	
	if not(session.type == "component" and stanza.attr.from == session.host) then return; end
	local from_node, from_host = jid_split(stanza.attr.to);
	if not(user_exists(from_node, from_host)) then return; end
	local roster = load_roster(from_node, from_host);
	if not(roster) then return; end

	local query = stanza.tags[1];
	if #query.tags == 1 and query.tags[1].name == "item"
			and query.tags[1].attr.xmlns == "jabber:iq:roster" and query.tags[1].attr.jid
			-- Protection against overwriting roster.pending, until we move it
			and query.tags[1].attr.jid ~= "pending" then
		local item = query.tags[1];
		local jid = jid_prep(item.attr.jid);
		local node, host, resource = jid_split(jid);
		if not resource and host then
			if jid ~= stanza.attr.to then
				if item.attr.subscription == "remove" then
					local r_item = roster[jid];
					if r_item then
						local to_bare = node and (node.."@"..host) or host; -- bare JID
						if r_item.subscription == "both" or r_item.subscription == "from" or (roster.pending and roster.pending[jid]) then
							core_post_stanza(session, st.presence({type="unsubscribed", from=session.full_jid, to=to_bare}));
						end
						if r_item.subscription == "both" or r_item.subscription == "to" or r_item.ask then
							core_post_stanza(session, st.presence({type="unsubscribe", from=session.full_jid, to=to_bare}));
						end
						local success, err_type, err_cond, err_msg = rm_remove_from_roster(session, jid);
						if success then
							session.send(st.reply(stanza));
							rm_roster_push(from_node, from_host, jid);
						else
							session.send(st.error_reply(stanza, err_type, err_cond, err_msg));
						end
					else
						session.send(st.error_reply(stanza, "modify", "item-not-found"));
					end
				else
					local r_item = {name = item.attr.name, groups = {}};
					if r_item.name == "" then r_item.name = nil; end
					if session.roster[jid] then
						r_item.subscription = session.roster[jid].subscription;
						r_item.ask = session.roster[jid].ask;
					else
						r_item.subscription = "none";
					end
					for _, child in ipairs(item) do
						if child.name == "group" then
							local text = t_concat(child);
							if text and text ~= "" then
								r_item.groups[text] = true;
							end
						end
					end
					local success, err_type, err_cond, err_msg = rm_add_to_roster(session, jid, r_item);
					if success then -- Ok, send success
						session.send(st.reply(stanza));
						-- and push change to all resources
						rm_roster_push(from_node, from_host, jid);
					else -- Adding to roster failed
						session.send(st.error_reply(stanza, err_type, err_cond, err_msg));
					end
				end
			else -- Trying to add self to roster
				session.send(st.error_reply(stanza, "cancel", "not-allowed"));
			end
		else -- Invalid JID added to roster
			session.send(st.error_reply(stanza, "modify", "bad-request")); -- FIXME what's the correct error?
		end
	else -- Roster set didn't include a single item, or its name wasn't  'item'
		session.send(st.error_reply(stanza, "modify", "bad-request"));
	end
	return true;
end);

function component_roster_push(node, host, jid)
	local roster = load_roster(node, host);
	if roster then
		local item = roster[jid];
		local contact_node, contact_host = jid_split(jid);
		local stanza = st.iq({ type="set", from=node.."@"..host, to=contact_host }):query("jabber:iq:roster");
		if item then
			stanza:tag("item", { jid = jid, subscription = item.subscription, name = item.name, ask = item.ask });
			for group in pairs(item.groups) do
				stanza:tag("group"):text(group):up();
			end
		else
			stanza:tag("item", {jid = jid, subscription = "remove"});
		end
		stanza:up(); -- move out from item
		stanza:up(); -- move out from stanza
		core_post_stanza(hosts[module.host], stanza);
	end
end

module:hook("iq-set/bare/jabber:iq:roster:query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local query = stanza.tags[1];
	local item = query.tags[1];
	local contact_jid = item and item.name == "item" and item.attr.jid ~= "pending" and item.attr.jid;
	if contact_jid then
		local contact_node, contact_host = jid_split(contact_jid);
		if hosts[contact_host] and hosts[contact_host].type == "component" then
			local node, host = jid_split(stanza.attr.to or origin.full_jid);
			add_task(0, function()
				component_roster_push(node, host, contact_jid);
			end);
		end
	end
end, 100);
