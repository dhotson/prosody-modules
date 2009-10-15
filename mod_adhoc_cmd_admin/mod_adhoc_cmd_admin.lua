-- Copyright (C) 2009 Florian Zeitz
-- 
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local _G = _G;

local prosody = _G.prosody;
local hosts = prosody.hosts;

local usermanager_user_exists = require "core.usermanager".user_exists;
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

function add_user_command_handler(item, origin, stanza)
	if not is_admin(stanza.attr.from) then
		module:log("warn", "Non-admin %s tried to add a user", tostring(jid.bare(stanza.attr.from)));
		origin.send(st.error_reply(stanza, "auth", "forbidden", "You don't have permission to add a user"):up()
			:add_child(item:cmdtag("canceled")
				:tag("note", {type="error"}):text("You don't have permission to add a user")));
		return true;
	end
	if stanza.tags[1].attr.sessionid and sessions[stanza.tags[1].attr.sessionid] then
		if stanza.tags[1].attr.action == "cancel" then
			origin.send(st.reply(stanza):add_child(item:cmdtag("canceled", stanza.tags[1].attr.sessionid)));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end
		form = stanza.tags[1]:child_with_ns("jabber:x:data");
		local fields = add_user_layout:data(form);
		local username, host, resource = jid.split(fields.accountjid);
		if (fields.password == fields["password-verify"]) and username and host and host == stanza.attr.to then
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

function get_online_users_command_handler(item, origin, stanza)
	if not is_admin(stanza.attr.from) then
		origin.send(st.error_reply(stanza, "auth", "forbidden", "You don't have permission to request a list of online users"):up()
			:add_child(item:cmdtag("canceled")
				:tag("note", {type="error"}):text("You don't have permission to request a list of online users")));
		return true;
	end
	local field = st.stanza("field", {label="The list of all online users", var="onlineuserjids", type="text-multi"});
	for username, user in pairs(hosts[stanza.attr.to].sessions or {}) do
		field:tag("value"):text(username.."@"..stanza.attr.to):up();
	end
	origin.send(st.reply(stanza):add_child(item:cmdtag("completed", uuid:generate())
		:tag("x", {xmlns="jabber:x:data", type="result"})
			:tag("field", {type="hidden", var="FORM_TYPE"})
				:tag("value"):text("http://jabber.org/protocol/admin"):up():up()
			:add_child(field)));

	return true;
end

local add_user_desc = adhoc_new("Add User", "http://jabber.org/protocol/admin#add-user", add_user_command_handler, "admin");
local get_online_users_desc = adhoc_new("Get List of Online Users", "http://jabber.org/protocol/admin#get-online-users", get_online_users_command_handler, "admin"); 

function module.unload()
	module:remove_item("adhoc", add_user_desc);
	module:remove_item("adhoc", get_online_users_desc);
end

module:add_item("adhoc", add_user_desc);
module:add_item("adhoc", get_online_users_desc);
