local add_filter = require "util.filters".add_filter;
local add_task = require "util.timer".add_task;

local buffer_seconds = module:get_option_number("flush_presence_seconds");

local function throttle_session(data)
	local session = data.session;
	local buffer, flushing = {}, false;
	local timer_active = false;
	local function flush_buffer()
		module:log("debug", "Flushing buffer for %s", session.full_jid);
		flushing = true;
		for jid, presence in pairs(buffer) do
			session.send(presence);
		end
		flushing = false;
	end
	local function throttle_presence(stanza)
		if stanza.name ~= "presence" or (stanza.attr.type and stanza.attr.type ~= "unavailable") then
			module:log("debug", "Non-presence stanza for %s: %s", session.full_jid, tostring(stanza));
			flush_buffer();
		elseif not flushing then
			module:log("debug", "Buffering presence stanza from %s to %s", stanza.attr.from, session.full_jid);
			buffer[stanza.attr.from] = stanza;
			if not timer_active and buffer_seconds then
				timer_active = true;
				add_task(buffer_seconds, flush_buffer);
			end
			return nil; -- Drop this stanza (we've stored it for later)
		end
		return stanza;
	end
	add_filter(session, "stanzas/out", throttle_presence);
end


module:hook("resource-bind", throttle_session);
