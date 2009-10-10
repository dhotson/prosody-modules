-- Copyright (C) 2009 Florian Zeitz
-- 
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st, jid, uuid = require "util.stanza", require "util.jid", require "util.uuid";
local dataforms_new = require "util.dataforms".new;
local usermanager_user_exists = require "core.usermanager".user_exists;
local usermanager_create_user = require "core.usermanager".create_user;

local is_admin = require "core.usermanager".is_admin;
local admins = set.new(config.get(module:get_host(), "core", "admins"));

local sessions = {};

local add_user_layout = dataforms_new{
	title= "Adding a User";
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
			:tag("command", {xmlns="http://jabber.org/protocol/commands",
				node="http://jabber.org/protocol/admin#add-user", status="canceled"})
			:tag("note", {type="error"}):text("You don't have permission to add a user"));
		return true;
	end
	if stanza.tags[1].attr.sessionid and sessions[stanza.tags[1].attr.sessionid] then
		if stanza.tags[1].attr.action == "cancel" then
			origin.send(st.reply(stanza):tag("command", {xmlns="http://jabber.org/protocol/commands",
				node="http://jabber.org/protocol/admin#add-user",
				sessionid=stanza.tags[1].attr.sessionid, status="canceled"}));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end
		form = stanza.tags[1]:find_child_with_ns("jabber:x:data");
		local fields = add_user_layout:data(form);
		local username, host, resource = jid.split(fields.accountjid);
		if (fields.password == fields["password-verify"]) and username and host and host == stanza.attr.to then
			if usermanager_user_exists(username, host) then
				origin.send(st.error_reply(stanza, "cancel", "conflict", "Account already exists"):up()
					:tag("command", {xmlns="http://jabber.org/protocol/commands",
						node="http://jabber.org/protocol/admin#add-user", status="canceled"})
					:tag("note", {type="error"}):text("Account already exists"));
				sessions[stanza.tags[1].attr.sessionid] = nil;
				return true;
			else
				if usermanager_create_user(username, fields.password, host) then
					origin.send(st.reply(stanza):tag("command", {xmlns="http://jabber.org/protocol/commands",
						node="http://jabber.org/protocol/admin#add-user",
						sessionid=stanza.tags[1].attr.sessionid, status="completed"})
						:tag("note", {type="info"}):text("Account successfully created"));
					sessions[stanza.tags[1].attr.sessionid] = nil;
					module:log("debug", "Created new account " .. username.."@"..host);
					return true;
				else
					origin.send(st.error_reply(stanza, "wait", "internal-server-error",
						"Failed to write data to disk"):up()
						:tag("command", {xmlns="http://jabber.org/protocol/commands",
							node="http://jabber.org/protocol/admin#add-user", status="canceled"})
						:tag("note", {type="error"}):text("Failed to write data to disk"));
					sessions[stanza.tags[1].attr.sessionid] = nil;
					return true;
				end
			end
		else
			module:log("debug", fields.accountjid .. " " .. fields.password .. " " .. fields["password-verify"]);
			origin.send(st.error_reply(stanza, "cancel", "conflict",
				"Invalid data.\nPassword mismatch, or empty username"):up()
				:tag("command", {xmlns="http://jabber.org/protocol/commands",
					node="http://jabber.org/protocol/admin#add-user", status="canceled"})
				:tag("note", {type="error"}):text("Invalid data.\nPassword mismatch, or empty username"));
			sessions[stanza.tags[1].attr.sessionid] = nil;
			return true;
		end
	else
		local sessionid=uuid.generate();
		sessions[sessionid] = "executing";
		origin.send(st.reply(stanza):tag("command", {xmlns="http://jabber.org/protocol/commands",
			node="http://jabber.org/protocol/admin#add-user", sessionid=sessionid,
			status="executing"}):add_child(add_user_layout:form()));
	end
	return true;
end

local descriptor = { name="Add User", node="http://jabber.org/protocol/admin#add-user", handler=add_user_command_handler };

function module.unload()
	module:remove_item("adhoc", descriptor);
end

module:add_item ("adhoc", descriptor);
