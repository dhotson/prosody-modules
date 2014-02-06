-- mod_manifesto

local timer = require "util.timer";
local jid_split = require "util.jid".split;
local st = require "util.stanza";
local dm = require "util.datamanager";
local time = os.time;

local hosts = prosody.hosts;
local host = module.host;
local host_session = hosts[host];
local incoming_s2s = prosody.incoming_s2s;

local default_tpl = [[
Hello there.

This is a brief system message to let you know about some upcoming changes to the $HOST service.

Some of your contacts are on other Jabber/XMPP services that do not support encryption.  As part of an initiative to increase the security of the Jabber/XMPP network, this service ($HOST) will be participating in a series of tests to discover the impact of our planned changes, and you may lose the ability to communicate with some of your contacts.

The test days well be on the following dates: January 4, February 22, March 22 and April 19.  On these days we will require that all client and server connections are encrypted.  Unless they enable encryption before that, you will be unable to communicate with your contacts that use these services:

$SERVICES

Your affected contacts are:

$CONTACTS

What can you do?  You may tell your contacts to inform their service administrator about their lack of encryption.  Your contacts may also switch to a more secure service.  A list of public services can be found at https://xmpp.net/directory.php

For more information about the Jabber/XMPP security initiative that we are participating in, please read the announcement at https://stpeter.im/journal/1496.html

If you have any questions or concerns, you may contact us via $CONTACTVIA at $CONTACT
]];

local message = module:get_option_string("manifesto_contact_encryption_warning", default_tpl);
local contact = module:get_option_string("admin_contact_address", module:get_option_array("admins", {})[1]);
if not contact then
	error("mod_manifesto needs you to set 'admin_contact_address' in your config file.", 0);
end
local contact_method = "Jabber/XMPP";
if select(2, contact:gsub("^mailto:", "")) > 0 then
	contact_method = "email";
end

local notified;

module:hook("resource-bind", function (event)
	local session = event.session;

	local now = time();
	local last_notify = notified[session.username] or 0;
	if last_notify > ( now - 86400 * 7 ) then
		return
	end

	timer.add_task(15, function ()
		if session.type ~= "c2s" then return end -- user quit already
		local bad_contacts, bad_hosts = {}, {};
		for contact_jid, item in pairs(session.roster or {}) do
			local _, contact_host = jid_split(contact_jid);
			local bad = false;
			local remote_host_session = host_session.s2sout[contact_host];
			if remote_host_session and remote_host_session.type == "s2sout" then -- Only check remote hosts we have completed s2s connections to
				if not remote_host_session.secure then
					bad = true;
				end
			end
			for session in pairs(incoming_s2s) do
				if session.to_host == host and session.from_host == contact_host and session.type == "s2sin" then
					if not session.secure then
						bad = true;
					end
				end
			end
			if bad then
				local contact_name = item.name;
				if contact_name then
					table.insert(bad_contacts, contact_name.." <"..contact_jid..">");
				else
					table.insert(bad_contacts, contact_jid);
				end
				if not bad_hosts[contact_host] then
					bad_hosts[contact_host] = true;
					table.insert(bad_hosts, contact_host);
				end
			end
		end
		if #bad_contacts > 0 then
			local vars = {
				HOST = host;
				CONTACTS = "    "..table.concat(bad_contacts, "\n    ");
				SERVICES = "    "..table.concat(bad_hosts, "\n    ");
				CONTACTVIA = contact_method, CONTACT = contact;
			};
			session.send(st.message({ type = "headline", from = host }):tag("body"):text(message:gsub("$(%w+)", vars)));
		end
		notified[session.username] = now;
	end);
end);

function module.load()
	notified = dm.load(nil, host, module.name) or {};
end

function module.save()
	dm.store(nil, host, module.name, notified);
	return { notified = notified };
end

function module.restore(data)
	notified = data.notified;
end

function module.unload()
	dm.store(nil, host, module.name, notified);
end

function module.uninstall()
	dm.store(nil, host, module.name, nil);
end
