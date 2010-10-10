-- Relay messages between rooms
-- By Kim Alvefur <zash@zash.se>

local host_session = prosody.hosts[module.host];
local st_msg = require "util.stanza".message;
local jid = require "util.jid";

function check_message(data)
	local origin, stanza = data.origin, data.stanza;
	local muc_rooms = host_session.muc and host_session.muc.rooms;
	if not muc_rooms then return; end

	local this_room = muc_rooms[stanza.attr.to];
	if not this_room then return; end -- no such room

	local from_room_jid = this_room._jid_nick[stanza.attr.from];
	if not from_room_jid then return; end -- no such nick

	local from_room, from_host, from_nick = jid.split(from_room_jid);

	local body = stanza:get_child("body");
	if not body then return; end -- No body, like topic changes
	body = body and body:get_text(); -- I feel like I want to do `or ""` there :/
	local target_room, message = body:match("^@([^:]+):(.*)");
	if not target_room or not message then return; end

	if target_room == from_room then return; end -- don't route to itself
	module:log("debug", "target room is %s", target_room);

	local bare_room = jid.join(target_room, from_host);
	if not muc_rooms[bare_room] then return; end -- TODO send a error
	module:log("info", "message from %s in %s to %s", from_nick, from_room, target_room);

	local sender = jid.join(target_room, module.host, from_room .. "/" .. from_nick);
	local forward_stanza = st_msg({from = sender, to = bare_room, type = "groupchat"}, message);

	module:log("debug", "broadcasting message to target room");
	muc_rooms[bare_room]:broadcast_message(forward_stanza);
end

module:hook("message/bare", check_message);
