-- Copyright (C) 2009 Thilo Cestonaro
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--
local prosody = prosody;
local splitJid = require "util.jid".split;
local bareJid = require "util.jid".bare;
local config_get = require "core.configmanager".get;

function logIfNeeded(e)
	local stanza, origin = e.stanza, e.origin;
	if (stanza.name == "presence") or 
	   (stanza.name == "message" and tostring(stanza.attr.type) == "groupchat")
	then
		local node, host, resource = splitJid(stanza.attr.to);
		if node ~= nil and host ~= nil then
			local bare = node .. "@" .. host;
			if prosody.hosts[host] ~= nil and prosody.hosts[host].muc ~= nil and prosody.hosts[host].muc.rooms[bare] ~= nil then
				local room = prosody.hosts[host].muc.rooms[bare]
				local logFolder = config_get(host, "core", "logFolder");
				if logFolder ~= nil then
					local today = os.date("%y%m%d");
					local now = os.date("%X")
					local fn = logFolder .. "/" .. today .. "_" .. bare .. ".log";
					local mucFrom = nil;
			
					if stanza.name == "presence" and stanza.attr.type == nil then
						mucFrom = stanza.attr.to;
					else
						for jid, nick in pairs(room._jid_nick) do
							if jid == stanza.attr.from then
								mucFrom = nick;
							end
						end
					end

					if mucFrom ~= nil then
						module:log("debug", "try to open room log: %s", fn);
						local f = assert(io.open(fn, "a"));
						local realFrom = stanza.attr.from;
						local realTo = stanza.attr.to;
						stanza.attr.from = mucFrom;
						stanza.attr.to = nil;
						f:write("<stanza time=\"".. now .. "\">" .. tostring(stanza) .. "</stanza>\n");
						stanza.attr.from = realFrom;
						stanza.attr.to = realTo;
						f:close()
					end
				end
			end
		end
	end
	return;
end

module:hook("pre-message/bare", logIfNeeded, 500);
module:hook("pre-presence/full", logIfNeeded, 500);

module:log("debug", "loaded ...");