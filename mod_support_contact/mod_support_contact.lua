-- mod_support_contact.lua
--
-- Config options:
--   support_contact = "support@hostname"; -- a JID
--   support_contact_nick = "Support!"; -- roster nick
--   support_contact_group = "Users being supported!"; -- the roster group in the support contact's roster

local host = module:get_host();

local support_contact = module:get_option("support_contact") or "support@"..host;
local support_contact_nick = module:get_option("support_contact_nick") or "Support";
local support_contact_group = module:get_option("support_contact_group") or "Users";

if not(support_contact and support_contact_nick) then return; end

local rostermanager = require "core.rostermanager";
local datamanager = require "util.datamanager";
local jid_split = require "util.jid".split;

module:hook("user-registered", function(event)
	module:log("debug", "Adding support contact");

	local groups = support_contact_group and {[support_contact_group] = true;} or {};

	local node, host = event.username, event.host;
	local jid = node and (node..'@'..host) or host;
	local roster;

	roster = rostermanager.load_roster(node, host) or {};
	roster[support_contact] = {subscription = "both", name = support_contact_nick, groups = {}};
	datamanager.store(node, host, "roster", roster);

	node, host = jid_split(support_contact);
	
	roster = rostermanager.load_roster(node, host) or {};
	roster[jid] = {subscription = "both", groups = groups};
	datamanager.store(node, host, "roster", roster);
	rostermanager.roster_push(node, host, jid);
end);
