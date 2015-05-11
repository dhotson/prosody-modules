local t_insert = table.insert;

local mod_smacks = module:depends"smacks"

local function store_unacked_stanzas(session)
	local queue = session.outgoing_stanza_queue;
	local replacement_queue = {};
	session.outgoing_stanza_queue = replacement_queue;

	for _, stanza in ipairs(queue) do
		if stanza.name == "message" and stanza.attr.xmlns == nil and
				( stanza.attr.type == "chat" or ( stanza.attr.type or "normal" ) == "normal" ) then
			module:fire_event("message/offline/handle", { origin = session, stanza = stanza } )
		else
			t_insert(replacement_queue, stanza);
		end
	end
end

local handle_unacked_stanzas = mod_smacks.handle_unacked_stanzas;

local host_sessions = prosody.hosts[module.host].sessions;
mod_smacks.handle_unacked_stanzas = function (session)
	if session.username then
		local sessions = host_sessions[session.username].sessions;
		if next(sessions) == session.resource and next(sessions, session.resource) == nil then
			store_unacked_stanzas(session)
		end
	end
	return handle_unacked_stanzas(session);
end

function module.unload()
	mod_smacks.handle_unacked_stanzas = handle_unacked_stanzas;
end
