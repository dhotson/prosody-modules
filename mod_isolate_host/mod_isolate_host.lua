local jid = require "util.jid";
local jid_bare, jid_split = jid.bare, jid.split;
local is_admin = require "core.usermanager".is_admin;
local set = require "util.set";
local st = require "util.stanza";

local stanza_types = set.new{"message", "presence", "iq"};
local jid_types = set.new{"bare", "full", "host"};

local except_domains = module:get_option_inherited_set("isolate_except_domains", {});
local except_users = module:get_option_inherited_set("isolate_except_users", {});

function check_stanza(event)
	local origin, stanza = event.origin, event.stanza;
	if origin.no_host_isolation then return; end
	local to_user, to_host = jid_split(event.stanza.attr.to);
	if to_host and to_host ~= origin.host and not except_domains:contains(to_host) then
		if to_host:match("^[^.]+%.(.+)$") == origin.host then -- Permit subdomains
			except_domains:add(to_host);
			return;
		end
		module:log("warn", "Forbidding stanza from %s to %s", stanza.attr.from or origin.full_jid, stanza.attr.to);
		origin.send(st.error_reply(stanza, "auth", "forbidden", "Communication with "..to_host.." is not available"));
		return true;
	end
end

for stanza_type in stanza_types do
	for jid_type in jid_types do
		module:hook("pre-"..stanza_type.."/"..jid_type, check_stanza);
	end
end

function check_user_isolated(event)
	local session = event.session;
	local bare_jid = jid_bare(session.full_jid);
	if is_admin(bare_jid, module.host) or except_users:contains(bare_jid) then
		session.no_host_isolation = true;
	end
	module:log("debug", "%s is %sisolated", session.full_jid or "[?]", session.no_host_isolation and "" or "not ");
end

module:hook("resource-bind", check_user_isolated);
