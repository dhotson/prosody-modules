-- Prosody IM
-- Copyright (C) 2010 Dai Zhiwei
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza";
local dm = require "util.datamanager"

module:add_feature("urn:xmpp:archive");
module:add_feature("urn:xmpp:archive:auto");
module:add_feature("urn:xmpp:archive:manage");
module:add_feature("urn:xmpp:archive:manual");
module:add_feature("urn:xmpp:archive:pref");

local function preferences_handler(event)
	local origin, stanza = event.origin, event.stanza;
	module:log("debug", "-- Enter preferences_handler()");
    module:log("debug", "-- pref:\n%s", tostring(stanza));
	if stanza.attr.type == "get" then
        -- dm.store(origin.username, origin.host, "archive_prefs", st.preserialize(reply.tags[1]));
        local data = st.deserialize(dm.load(origin.username, origin.host, "archive_prefs"));
        if data then
            origin.send(st.reply(stanza):add_child(data));
        else
            local reply = st.reply(stanza):tag('pref', {xmlns='urn:xmpp:archive'});
            reply:tag('default', {otr='concede', save='false', unset='true'}):up();
            reply:tag('method', {type='auto', use='concede'}):up();
            reply:tag('method', {type='local', use='concede'}):up();
            reply:tag('method', {type='manual', use='concede'}):up();
            reply:tag('auto', {save='false'}):up();
            origin.send(reply);
            -- origin.send(st.reply(stanza));
        end
		return true;
    elseif stanza.attr.type == "set" then
        return false;
	end
end

local function auto_handler(event)
    module:log("debug", "-- stanza:\n%s", tostring(event.stanza));
	if event.stanza.attr.type == "set" then
        event.origin.send(st.error_reply(event.stanza, "cancel", "feature-not-implemented"));
        return true;
    end
end

local function chat_handler(event)
    module:log("debug", "-- stanza:\n%s", tostring(event.stanza));
    return true;
end

local function itemremove_handler(event)
    module:log("debug", "-- stanza:\n%s", tostring(event.stanza));
    return true;
end

local function list_handler(event)
    module:log("debug", "-- stanza:\n%s", tostring(event.stanza));
    return true;
end

local function modified_handler(event)
    module:log("debug", "-- stanza:\n%s", tostring(event.stanza));
    return true;
end

local function remove_handler(event)
    module:log("debug", "-- stanza:\n%s", tostring(event.stanza));
    return true;
end

local function retrieve_handler(event)
    module:log("debug", "-- stanza:\n%s", tostring(event.stanza));
    return true;
end

local function save_handler(event)
    module:log("debug", "-- stanza:\n%s", tostring(event.stanza));
    return true;
end

module:hook("iq/self/urn:xmpp:archive:pref", preferences_handler);
module:hook("iq/self/urn:xmpp:archive:auto", auto_handler);
module:hook("iq/self/urn:xmpp:archive:chat", chat_handler);
module:hook("iq/self/urn:xmpp:archive:itemremove", itemremove_handler);
module:hook("iq/self/urn:xmpp:archive:list", list_handler);
module:hook("iq/self/urn:xmpp:archive:modified", modified_handler);
module:hook("iq/self/urn:xmpp:archive:remove", remove_handler);
module:hook("iq/self/urn:xmpp:archive:retrieve", retrieve_handler);
module:hook("iq/self/urn:xmpp:archive:save", save_handler);

