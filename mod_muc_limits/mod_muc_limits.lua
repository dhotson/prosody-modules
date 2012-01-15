
local st = require "util.stanza";
local new_throttle = require "util.throttle".create;

local period = math.max(module:get_option_number("muc_event_rate", 0.5), 0);
local burst = math.max(module:get_option_number("muc_burst_factor", 6), 1);

local function handle_stanza(event)
	local origin, stanza = event.origin, event.stanza;
	local dest_room, dest_host, dest_nick = jid.split(stanza.attr.to);
	local room = hosts[module.host].modules.muc.rooms[dest_room.."@"..dest_host];
	if not room then return; end
	local from_jid = stanza.attr.from;
	local occupant = room._occupants[room._jid_nick[from_jid]];
	if occupant and occupant.affiliation then
		module:log("debug", "Skipping stanza from affiliated user...");
		return;
	end
	local throttle = room.throttle;
	if not room.throttle then
		throttle = new_throttle(period*burst, burst);
		room.throttle = throttle;
	end
	if not throttle:poll(1) then
		module:log("warn", "Dropping stanza for %s@%s from %s, over rate limit", dest_room, dest_host, from_jid);
		origin.send(st.error_reply(stanza, "wait", "policy-violation", "The room is currently overactive, please try again later"));
		return true;
	end
end

module:hook("message/bare", handle_stanza, 10);
module:hook("message/full", handle_stanza, 10);
module:hook("presence/bare", handle_stanza, 10);
module:hook("presence/full", handle_stanza, 10);
