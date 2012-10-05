-- Password policy enforcement for Prosody
--
-- Copyright (C) 2012 Waqas Hussain
--
--
-- Configuration:
--    password_policy = {
--        length = 8;
--    }


local options = module:get_option("password_policy");

options = options or {};
options.length = options.length or 8;

local st = require "util.stanza";

function check_password(password)
	return #password <= options.length;
end

function handler(event)
	local origin, stanza = event.origin, event.stanza;

	if stanza.attr.type == "set" then
		local query = stanza.tags[1];

		local passwords = {};

		local dataform = query:get_child("x", "jabber:x:data");
		if dataform then
			for _,tag in ipairs(dataform.tags) do
				if tag.attr.var == "password" then
					table.insert(passwords, tag:get_child_text("value"));
				end
			end
		end

		table.insert(passwords, query:get_child_text("password"));

		for _,password in ipairs(passwords) do
			if password and not check_password(password) then
				origin.send(st.error_reply(stanza, "cancel", "not-acceptable", "Please use a longer password."));
				return true;
			end
		end
	end
end

module:hook("iq/self/jabber:iq:register:query", handler, 10);
module:hook("iq/host/jabber:iq:register:query", handler, 10);
module:hook("stanza/iq/jabber:iq:register:query", handler, 10);
