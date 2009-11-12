-- Copyright (C) 2009 Florian Zeitz
-- 
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local _G = _G;

local prosody = _G.prosody;
local hosts = prosody.hosts;

local t_concat = table.concat;

local usermanager_user_exists = require "core.usermanager".user_exists;
local usermanager_get_password = require "core.usermanager".get_password;
local usermanager_create_user = require "core.usermanager".create_user;
local is_admin = require "core.usermanager".is_admin;

local st, jid, uuid = require "util.stanza", require "util.jid", require "util.uuid";
local dataforms_new = require "util.dataforms".new;
local adhoc_new = module:require "adhoc".new;

local sessions = {};

local add_user_layout = dataforms_new{
	title = "Adding a User";
	instructions = "Fill out this form to add a user.";

	{ name = "FORM_TYPE", type = "hidden", value = "http://jabber.org/protocol/admin" };
	{ name = "accountjid", type = "jid-single", required = true, label = "The Jabber ID for the account to be added" };
	{ name = "password", type = "text-private", label = "The password for this account" };
	{ name = "password-verify", type = "text-private", label = "Retype password" };
};

local delete_user_layout = dataforms_new{
	title = "Deleting a User";
	instructions = "Fill out this form to delete a user.";

	{ name = "FORM_TYPE", type = "hidden", value = "http://jabber.org/protocol/admin" };
	{ name = "accountjids", type = "jid-multi", label = "The Jabber ID(s) to delete" };
};

local get_user_password_layout = dataforms_new{
	title = "Getting Users' Passwords";
	instructions = "Fill out this form to get users' passwords.";

	{ name = "FORM_TYPE", type = "hidden", value = "http://jabber.org/protocol/admin" };
	{ name = "accountjids", type = "jid-multi", label = "The Jabber ID(s) for which to retrieve the password" };
};

local get_online_users_layout = dataforms_new{
	title = "Getting List of Online Users";
	instructions = "How many users should be returned at most?";

	{ name = "FORM_TYPE", type = "hidden", value = "http://jabber.org/protocol/admin" };
	{ name = "max_items", type = "list-single", label = "Maximum number of users",
		value = { "25", "50", "75", "100", "150", "200", "all" } };
};

local announce_layout = dataforms_new{
	title = "Making an Announcement";
	instructions = "Fill out this form to make an announcement to all\nactive users of this service.";

	{ name = "FORM_TYPE", type = "hidden", value = "http://jabber.org/protocol/admin" };
	{ name = "subject", type = "text-single", label = "Subject" };
	{ name = "announcement", type = "text-multi", required = true, label = "Announcement" };
};

function add_user_command_handler(item, origin, stanza)
	if stanza.tags[1].attr.sessionid and sessions[stanza.tags[1].attr.sessionid] then
		if stanza.tags[1].attr.action == "cancel" then
			origin.send(st.reply(stanza):add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end
		local form = stanza.tags[1]:child_with_ns("jabber:x:data");
		local fields = add_user_layout:data(form);
		local username, host, resource = jid.split(fields.accountjid);
		if (fields["password"] == fields["password-verify"]) and username and host and host == stanza.attr.to then
			if usermanager_user_exists(username, host) then
				origin.send(st.error_reply(stanza, "cancel", "conflict", "Account already exists"):up()
					:add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)
						:tag("note", {type="error"}):text("Account already exists")));
				sessions[stanza.tags[1].attr.sessionid] = nil;
				return true;
			else
				if usermanager_create_user(username, fields.password, host) then
					origin.send(st.reply(stanza):add_child(item:cmdtag("completed", stanza.tags[1].attr.sessionid)
						:tag("note", {type="info"}):text("Account successfully created")));
					sessions[stanza.tags[1].attr.sessionid] = nil;
					module:log("debug", "Created new account " .. username.."@"..host);
					return true;
				else
					origin.send(st.error_reply(stanza, "wait", "internal-server-error",
						"Failed to write data to disk"):up()
						:add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)
							:tag("note", {type="error"}):text("Failed to write data to disk")));
					sessions[stanza.tags[1].attr.sessionid] = nil;
					return true;
				end
			end
		else
			module:log("debug", fields.accountjid .. " " .. fields.password .. " " .. fields["password-verify"]);
			origin.send(st.error_reply(stanza, "cancel", "conflict",
				"Invalid data.\nPassword mismatch, or empty username"):up()
				:add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)
					:tag("note", {type="error"}):text("Invalid data.\nPassword mismatch, or empty username")));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end
	else
		local sessionid=uuid.generate();
		sessions[sessionid] = "executing";
		origin.send(st.reply(stanza):add_child(item:cmdtag("executing", sessionid):add_child(add_user_layout:form())));
	end
	return true;
end

function delete_user_command_handler(item, origin, stanza)
	if stanza.tags[1].attr.sessionid and sessions[stanza.tags[1].attr.sessionid] then
		if stanza.tags[1].attr.action == "cancel" then
			origin.send(st.reply(stanza):add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end
		local form = stanza.tags[1]:child_with_ns("jabber:x:data");
		local fields = delete_user_layout:data(form);
		local failed = {};
		local succeeded = {};
		for _, aJID in ipairs(fields.accountjids) do
			local username, host, resource = jid.split(aJID);
			if usermanager_user_exists(username, host) and usermanager_create_user(username, nil, host) then
				module:log("debug", "User" .. aJID .. "has been deleted");
				succeeded[#succeeded+1] = aJID;
			else
				module:log("debug", "Tried to delete not existing user "..aJID);
				failed[#failed+1] = aJID;
			end
		end
		origin.send(st.reply(stanza):add_child(item:cmdtag("completed", stanza.tags[1].attr.sessionid)
			:tag("note", {type="info"})
				:text((#succeeded ~= 0 and "The following accounts were successfully deleted:\n"..t_concat(succeeded, "\n").."\n" or "")
					..(#failed ~= 0 and "The following accounts could not be deleted:\n"..t_concat(failed, "\n") or ""))));
		sessions[stanza.tags[1].attr.sessionid] = nil;
		return true;
	else
		local sessionid=uuid.generate();
		sessions[sessionid] = "executing";
		origin.send(st.reply(stanza):add_child(item:cmdtag("executing", sessionid):add_child(delete_user_layout:form())));
	end
	return true;
end

function get_user_password_handler(item, origin, stanza)
	if stanza.tags[1].attr.sessionid and sessions[stanza.tags[1].attr.sessionid] then
		if stanza.tags[1].attr.action == "cancel" then
			origin.send(st.reply(stanza):add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end
		local form = stanza.tags[1]:child_with_ns("jabber:x:data");
		local fields = get_user_password_layout:data(form);
		local accountjids = st.stanza("field", {var="accountjids", label = "JIDs", type="jid-multi"});
		local passwords = st.stanza("field", {var="password", label = "Passwords", type="text-multi"});
		for _, aJID in ipairs(fields.accountjids) do
			user, host, resource = jid.split(aJID);
			if usermanager_user_exists(user, host) then
				accountjids:tag("value"):text(aJID):up();
				passwords:tag("value"):text(usermanager_get_password(user, host)):up();
			end
		end
		origin.send(st.reply(stanza):add_child(item:cmdtag("completed", stanza.tags[1].attr.sessionid)
			:tag("x", {xmlns="jabber:x:data", type="result"})
				:tag("field", {type="hidden", var="FORM_TYPE"})
					:tag("value"):text("http://jabber.org/protocol/admin"):up():up()
				:add_child(accountjids)
				:add_child(passwords)));
		sessions[stanza.tags[1].attr.sessionid] = nil;
		return true;
	else
		local sessionid=uuid.generate();
		sessions[sessionid] = "executing";
		origin.send(st.reply(stanza):add_child(item:cmdtag("executing", sessionid):add_child(get_user_password_layout:form())));
	end
	return true;
end

function get_online_users_command_handler(item, origin, stanza)
	if stanza.tags[1].attr.sessionid and sessions[stanza.tags[1].attr.sessionid] then
		if stanza.tags[1].attr.action == "cancel" then
			origin.send(st.reply(stanza):add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end

		local form = stanza.tags[1]:child_with_ns("jabber:x:data");
		local fields = add_user_layout:data(form);
		
		local max_items = nil
		if fields.max_items ~= "all" then
			max_items = tonumber(fields.max_items);
		end
		local count = 0;
		local field = st.stanza("field", {label="The list of all online users", var="onlineuserjids", type="text-multi"});
		for username, user in pairs(hosts[stanza.attr.to].sessions or {}) do
			if (max_items ~= nil) and (count >= max_items) then
				break;
			end
			field:tag("value"):text(username.."@"..stanza.attr.to):up();
			count = count + 1;
		end
		origin.send(st.reply(stanza):add_child(item:cmdtag("completed", stanza.tags[1].attr.sessionid)
			:tag("x", {xmlns="jabber:x:data", type="result"})
				:tag("field", {type="hidden", var="FORM_TYPE"})
					:tag("value"):text("http://jabber.org/protocol/admin"):up():up()
				:add_child(field)));
		sessions[stanza.tags[1].attr.sessionid] = nil;
		return true;
	else
		local sessionid=uuid.generate();
		sessions[sessionid] = "executing";
		origin.send(st.reply(stanza):add_child(item:cmdtag("executing", sessionid):add_child(get_online_users_layout:form())));
	end

	return true;
end

function announce_handler(item, origin, stanza)
	if stanza.tags[1].attr.sessionid and sessions[stanza.tags[1].attr.sessionid] then
		if stanza.tags[1].attr.action == "cancel" then
			origin.send(st.reply(stanza):add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end

		local form = stanza.tags[1]:child_with_ns("jabber:x:data");
		local fields = add_user_layout:data(form);

		module:log("info", "Sending server announcement to all online users");
		local host_session = hosts[stanza.attr.to];
		local message = st.message({type = "headline", from = stanza.attr.to}, fields.announcement):up()
			:tag("subject"):text(fields.subject or "Announcement");
		
		local c = 0;
		for user in pairs(host_session.sessions) do
			c = c + 1;
			message.attr.to = user.."@"..stanza.attr.to;
			core_post_stanza(host_session, message);
		end
		
		module:log("info", "Announcement sent to %d online users", c);

		origin.send(st.reply(stanza):add_child(item:cmdtag("completed", stanza.tags[1].attr.sessionid)
			:tag("note"):text("Announcement sent.")));
		sessions[stanza.tags[1].attr.sessionid] = nil;
		return true;
	else
		local sessionid=uuid.generate();
		sessions[sessionid] = "executing";
		origin.send(st.reply(stanza):add_child(item:cmdtag("executing", sessionid):add_child(announce_layout:form())));
	end

	return true;
end

local add_user_desc = adhoc_new("Add User", "http://jabber.org/protocol/admin#add-user", add_user_command_handler, "admin");
local delete_user_desc = adhoc_new("Delete User", "http://jabber.org/protocol/admin#delete-user", delete_user_command_handler, "admin");
local get_user_password_desc = adhoc_new("Get User Password", "http://jabber.org/protocol/admin#get-user-password", get_user_password_handler, "admin");
local get_online_users_desc = adhoc_new("Get List of Online Users", "http://jabber.org/protocol/admin#get-online-users", get_online_users_command_handler, "admin"); 
local announce_desc = adhoc_new("Send Announcement to Online Users", "http://jabber.org/protocol/admin#announce", announce_handler, "admin");

function module.unload()
	module:remove_item("adhoc", add_user_desc);
	module:remove_item("adhoc", delete_user_desc);
	module:remove_item("adhoc", get_user_password_desc);
	module:remove_item("adhoc", get_online_users_desc);
	module:remove_item("adhoc", announce_desc);
end

module:add_item("adhoc", add_user_desc);
module:add_item("adhoc", delete_user_desc);
module:add_item("adhoc", get_user_password_desc);
module:add_item("adhoc", get_online_users_desc);
module:add_item("adhoc", announce_desc);
