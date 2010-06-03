module:add_feature("urn:xmpp:blocking");

-- Add JID to default privacy list
function add_blocked_jid(username, host, jid)
	local privacy_lists = datamanager.load(username, host, "privacy") or {};
	local default_list_name = privacy_lists.default;
	if not default_list_name then
		default_list_name = "blocklist";
		privacy_lists.default = default_list_name;
	end
	local default_list = privacy_lists.list[default_list_name];
	if not default_list then
		default_list = { name = default_list_name, items = {} };
		privacy_lists.lists[default_list_name] = default_list;
	end
	local items = default_list.items;
	local order = items[1].order; -- Must come first
	for i=1,#items do -- order must be unique
		items[i].order = items[i].order + 1;
	end
	table.insert(items, 1, { type = "jid"
		, action = "deny"
		, value = jid
		, message = false
		, ["presence-out"] = false
		, ["presence-in"] = false
		, iq = false
		, order = order
	};
	datamanager.store(username, host, "privacy", privacy_lists);
end

-- Remove JID from default privacy list
function remove_blocked_jid(username, host, jid)
	local privacy_lists = datamanager.load(username, host, "privacy") or {};
	local default_list_name = privacy_lists.default;
	if not default_list_name then return; end
	local default_list = privacy_lists.list[default_list_name];
	if not default_list then return; end
	local items = default_list.items;
	local item;
	for i=1,#items do -- order must be unique
		item = items[i];
		if item.type == "jid" and item.action == "deny" and item.value == jid then
			table.remove(items, i);
			return true;
		end
	end
	datamanager.store(username, host, "privacy", privacy_lists);
end

function remove_all_blocked_jids(username, host)
	local privacy_lists = datamanager.load(username, host, "privacy") or {};
	local default_list_name = privacy_lists.default;
	if not default_list_name then return; end
	local default_list = privacy_lists.list[default_list_name];
	if not default_list then return; end
	local items = default_list.items;
	local item;
	for i=#items,1 do -- order must be unique
		item = items[i];
		if item.type == "jid" and item.action == "deny" then
			table.remove(items, i);
		end
	end
	datamanager.store(username, host, "privacy", privacy_lists);
end

function get_blocked_jids(username, host)
	-- Return array of blocked JIDs in default privacy list
	local privacy_lists = datamanager.load(username, host, "privacy") or {};
	local default_list_name = privacy_lists.default;
	if not default_list_name then return {}; end
	local default_list = privacy_lists.list[default_list_name];
	if not default_list then return {}; end
	local items = default_list.items;
	local item;
	local jid_list = {};
	for i=1,#items do -- order must be unique
		item = items[i];
		if item.type == "jid" and item.action == "deny" then
			jid_list[#jid_list+1] = item.value;
		end
	end
	return jid_list;
end

function handle_blocking_command(session, stanza)
	local username, host = jid_split(stanza.attr.from);
	if stanza.attr.type == "set" then
		if stanza.tags[1].name == "block" then
			local block = stanza.tags[1]:get_child("block");
			local block_jid_list = {};
			for item in block:childtags() do
				block_jid_list[#block_jid_list+1] = item.attr.jid;
			end
			if #block_jid_list == 0 then
				--FIXME: Reply bad-request
			else
				for _, jid in ipairs(block_jid_list) do
					add_blocked_jid(username, host, jid);
				end
				session.send(st.reply(stanza));
			end
		elseif stanza.tags[1].name == "unblock" then
			remove_all_blocked_jids(username, host);
			session.send(st.reply(stanza));
		end
	elseif stanza.attr.type == "get" and stanza.tags[1].name == "blocklist" then
		local reply = st.reply(stanza):tag("blocklist", { xmlns = xmlns_block });
		local blocked_jids = get_blocked_jids(username, host);
		for _, jid in ipairs(blocked_jids) do
			reply:tag("item", { jid = jid }):up();
		end
		session.send(reply);
	else
		--FIXME: Need to respond with service-unavailable
	end
end

module:add_iq_handler("c2s", xmlns_blocking, handle_blocking_command);
