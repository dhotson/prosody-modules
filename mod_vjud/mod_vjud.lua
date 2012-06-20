local dm_load = require "util.datamanager".load;
local dm_store = require "util.datamanager".store;

local usermanager = require "core.usermanager";
local dataforms_new = require "util.dataforms".new;
local jid_split = require "util.jid".prepped_split;
local vcard = module:require "vcard";

local st = require "util.stanza";
local template = require "util.template";

local get_reply = template[[
<query xmlns="jabber:iq:search">
  <instructions>Fill in one or more fields to search for any matching Jabber users.</instructions>
  <first/>
  <last/>
  <nick/>
  <email/>
</query>
]].apply({});
local item_template = template[[
<item xmlns="jabber:iq:search" jid="{jid}">
  <first>{first}</first>
  <last>{last}</last>
  <nick>{nick}</nick>
  <email>{email}</email>
</item>
]];

module:add_feature("jabber:iq:search");

local opted_in;
function module.load()
	opted_in = dm_load(nil, module.host, "user_index") or {};
end
function module.unload()
	dm_store(nil, module.host, "user_index", opted_in);
end

local opt_in_layout = dataforms_new{
	title = "Search settings";
	instructions = "Do you want to appear in search results?";
	{
		name = "searchable",
		label = "Appear in search results?",
		type = "boolean",
	},
};
local vCard_mt = {
	__index = function(t, k)
		for i=1,#t do
			if t[i].name == k then
				t[k] = t[i];
				return t[i]
			end
		end
	end
};

local function get_user_vcard(user)
	local vCard = dm_load(user, module.host, "vcard");
	if vCard then
		vCard = st.deserialize(vCard);
		vCard = vcard.xep54_to_lua(vCard);
		return setmetatable(vCard, vCard_mt);
	end
end

local at_host = "@"..module.host;

module:hook("iq/host/jabber:iq:search:query", function(event)
	local origin, stanza = event.origin, event.stanza;

	if stanza.attr.type == "get" then
		origin.send(st.reply(stanza):add_child(get_reply));
	else -- type == "set"
		local query = stanza.tags[1];
		local reply = st.reply(stanza):query("jabber:iq:search");
		local first, last, nick, email =
			query:get_child_text"first",
			query:get_child_text"last",
			query:get_child_text"nick",
			query:get_child_text"email";
		first = first and #first and first;
		last = last and #last and last;
		nick = nick and #nick and nick;
		email = email and #email and email;
		local username, hostname = jid_split(email);
		if hostname == module.host and username and usermanager.user_exists(username, hostname) then
			local vCard = get_user_vcard(username);
			if vCard then
				reply:add_child(item_template.apply{
					jid = username..at_host;
					first = vCard.N and vCard.N[1] or nil;
					last = vCard.N and vCard.N[2] or nil;
					nick = vCard.NICKNAME and vCard.NICKNAME[1] or username;
					email = vCard.EMAIL and vCard.EMAIL[1] or nil;
				});
			end
		else
			for username in pairs(opted_in) do
				local vCard = get_user_vcard(username);
				if vCard and (
				(not first or (vCard.N and vCard.N[2] == first)) or
				(not last or (vCard.N and vCard.N[1] == last)) or
				(not nick or (vCard.NICKNAME and vCard.NICKNAME[1] == nick)) or
				(not email or (vCard.EMAIL and vCard.EMAIL[1] == email))) then
					reply:add_child(item_template.apply{
						jid = username..at_host;
						first = vCard.N and vCard.N[1] or nil;
						last = vCard.N and vCard.N[2] or nil;
						nick = vCard.NICKNAME and vCard.NICKNAME[1] or username;
						email = vCard.EMAIL and vCard.EMAIL[1] or nil;
					});
				end
			end
		end
		origin.send(reply);
	end
	return true;
end);

local function opt_in_handler(self, data, state)
	local username, hostname = jid_split(data.from);
	if state then -- the second return value
		if data.action == "cancel" then
			return { status = "canceled" };
		end

		if not username or not hostname or hostname ~= module.host then
			return { status = "error", error = { type = "cancel",
				condition = "forbidden", message = "Invalid user or hostname." } };
		end

		local fields = opt_in_layout:data(data.form);
		opted_in[username] = fields.searchable or nil

		return { status = "completed" }
	else -- No state, send the form.
		return { status = "executing", actions  = { "complete" },
			form = { layout = opt_in_layout, data = { searchable = opted_in[username] } } }, true;
	end
end

local adhoc_new = module:require "adhoc".new;
local adhoc_vjudsetup = adhoc_new("Search settings", "vjudsetup", opt_in_handler);--, "self");-- and nil);
module:depends"adhoc";
module:provides("adhoc", adhoc_vjudsetup);

