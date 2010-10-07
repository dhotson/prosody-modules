local st = require "util.stanza";

local t_insert, t_remove = table.insert, table.remove;
local math_min = math.min;
local tonumber, tostring = tonumber, tostring;
local add_filter = require "util.filters".add_filter;
local timer = require "util.timer";

local xmlns_sm = "urn:xmpp:sm:2";

local sm_attr = { xmlns = xmlns_sm };

local resume_timeout = 300;
local max_unacked_stanzas = 0;

module:add_event_hook("stream-features",
		function (session, features)
			features:tag("sm", sm_attr):tag("optional"):up():up();
		end);

module:hook("s2s-stream-features",
		function (data)
			data.features:tag("sm", sm_attr):tag("optional"):up():up();
		end);

module:hook_stanza(xmlns_sm, "enable",
		function (session, stanza)
			module:log("debug", "Enabling stream management");
			session.smacks = true;
			
			-- Overwrite process_stanza() and send()
			local queue = {};
			session.outgoing_stanza_queue = queue;
			session.last_acknowledged_stanza = 0;
			local _send = session.sends2s or session.send;
			local function new_send(stanza)
				local attr = stanza.attr;
				if attr and not attr.xmlns then -- Stanza in default stream namespace
					queue[#queue+1] = st.clone(stanza);
				end
				local ok, err = _send(stanza);
				if ok and #queue > max_unacked_stanzas and not session.awaiting_ack then
					session.awaiting_ack = true;
					return _send(st.stanza("r", { xmlns = xmlns_sm }));
				end
				return ok, err;
			end
			
			if session.sends2s then
				session.sends2s = new_send;
			else
				session.send = new_send;
			end
			
			session.handled_stanza_count = 0;
			add_filter(session, "stanzas/in", function (stanza)
				if not stanza.attr.xmlns then
					session.handled_stanza_count = session.handled_stanza_count + 1;
					session.log("debug", "Handled %d incoming stanzas", session.handled_stanza_count);
				end
				return stanza;
			end);

			if not stanza.attr.resume then -- FIXME: Resumption should be a different spec :/
				_send(st.stanza("enabled", sm_attr));
				return true;
			end
		end, 100);

module:hook_stanza(xmlns_sm, "r", function (origin, stanza)
	if not origin.smacks then
		module:log("debug", "Received ack request from non-smack-enabled session");
		return;
	end
	module:log("debug", "Received ack request, acking for %d", origin.handled_stanza_count);
	-- Reply with <a>
	(origin.sends2s or origin.send)(st.stanza("a", { xmlns = xmlns_sm, h = tostring(origin.handled_stanza_count) }));
	return true;
end);

module:hook_stanza(xmlns_sm, "a", function (origin, stanza)
	if not origin.smacks then return; end
	origin.awaiting_ack = nil;
	-- Remove handled stanzas from outgoing_stanza_queue
	local handled_stanza_count = tonumber(stanza.attr.h)-origin.last_acknowledged_stanza;
	local queue = origin.outgoing_stanza_queue;
	if handled_stanza_count > #queue then
		module:log("warn", "The client says it handled %d new stanzas, but we only sent %d :)",
			handled_stanza_count, #queue);
		for i=1,#queue do
			module:log("debug", "Q item %d: %s", i, tostring(queue[i]));
		end
	end
	for i=1,math_min(handled_stanza_count,#queue) do
		t_remove(origin.outgoing_stanza_queue, 1);
	end
	origin.last_acknowledged_stanza = origin.last_acknowledged_stanza + handled_stanza_count;
	return true;
end);

--TODO: Optimise... incoming stanzas should be handled by a per-session
-- function that has a counter as an upvalue (no table indexing for increments,
-- and won't slow non-198 sessions). We can also then remove the .handled flag
-- on stanzas

function handle_unacked_stanzas(session)
	local queue = session.outgoing_stanza_queue;
	local error_attr = { type = "cancel" };
	if #queue > 0 then
		session.outgoing_stanza_queue = {};
		for i=1,#queue do
			local reply = st.reply(queue[i]);
			if reply.attr.to ~= session.full_jid then
				reply.attr.type = "error";
				reply:tag("error", error_attr)
					:tag("recipient-unavailable", {xmlns = "urn:ietf:params:xml:ns:xmpp-stanzas"});
				core_process_stanza(session, reply);
			end
		end
	end
end

local _destroy_session = sessionmanager.destroy_session;
function sessionmanager.destroy_session(session, err)
	if session.smacks then
		if not session.resumption_token then
			local queue = session.outgoing_stanza_queue;
			if #queue > 0 then
				module:log("warn", "Destroying session with %d unacked stanzas:", #queue);
				for i=1,#queue do
					module:log("warn", "::%s", tostring(queue[i]));
				end
				handle_unacked_stanzas(session);
			end
		else
			session.hibernating = true;
			timer.add_task(resume_timeout, function ()
				if session.hibernating then
					session.resumption_token = nil;
					sessionmanager.destroy_session(session); -- Re-destroy
				end
			end);
			return; -- Postpone destruction for now
		end
	end
	return _destroy_session(session, err);
end
