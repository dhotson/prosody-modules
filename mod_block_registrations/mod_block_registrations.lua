local st = require "util.stanza";
local nodeprep = require "util.encodings".stringprep.nodeprep;

local block_users = module:get_option_set("block_registrations_users", { "admin" });
local block_patterns = module:get_option_set("block_registrations_matching", {});
local require_pattern = module:get_option_string("block_registrations_require");

function is_blocked(username)
        -- Check if the username is simply blocked
        if block_users:contains(username) then return true; end

        for pattern in block_patterns do
                if username:match(pattern) then
                        return true;
                end
        end
        -- Not blocked, but check that username matches allowed pattern
        if require_pattern and not username:match(require_pattern) then
                return true;
        end
end

module:hook("stanza/iq/jabber:iq:register:query", function(event)
        local session, stanza = event.origin, event.stanza;

        if stanza.attr.type == "set" then
                local query = stanza.tags[1];
                local username = nodeprep(query:get_child_text("username"));
                if username and is_blocked(username) then
                        session.send(st.error_reply(stanza, "modify", "policy-violation", "Username is blocked"));
                        return true;
                end
        end
end, 10);
