-- Prosody IM
-- Copyright (C) 2010 Dai Zhiwei
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza";
local dm = require "util.datamanager";

local PREFS_DIR = "archive_prefs";
local ARCHIVE_DIR = "archive";

module:add_feature("urn:xmpp:archive");
module:add_feature("urn:xmpp:archive:auto");
module:add_feature("urn:xmpp:archive:manage");
module:add_feature("urn:xmpp:archive:manual");
module:add_feature("urn:xmpp:archive:pref");

------------------------------------------------------------
-- Utils
------------------------------------------------------------
local function load_prefs(node, host, dir)
    return st.deserialize(dm.load(node, host, dir or PREFS_DIR));
end

local function store_prefs(data, node, host, dir)
    dm.store(node, host, dir or PREFS_DIR, st.preserialize(data));
end

------------------------------------------------------------
-- Preferences
------------------------------------------------------------
local function preferences_handler(event)
    local origin, stanza = event.origin, event.stanza;
    module:log("debug", "-- Enter preferences_handler()");
    module:log("debug", "-- pref:\n%s", tostring(stanza));
    if stanza.attr.type == "get" then
        local data = load_prefs(origin.username, origin.host);
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
        end
    elseif stanza.attr.type == "set" then
        local node, host = origin.username, origin.host;
        local data = load_prefs(node, host);
        if not data then
            data = st.stanza('pref', {xmlns='urn:xmpp:archive'});
            data:tag('default', {otr='concede', save='false'}):up();
            data:tag('method', {type='auto', use='concede'}):up();
            data:tag('method', {type='local', use='concede'}):up();
            data:tag('method', {type='manual', use='concede'}):up();
            data:tag('auto', {save='false'}):up();
        end
        local elem = stanza.tags[1].tags[1]; -- iq:pref:xxx
        if not elem then return false end
        -- "default" | "item" | "session" | "method"
        -- FIXME there may be many item/session/method sections!! 
        elem.attr["xmlns"] = nil; -- TODO why there is an extra xmlns attr?
        if elem.name == "default" then
            local setting = data:child_with_name(elem.name)
            for k, v in pairs(elem.attr) do
                setting.attr[k] = v;
            end
            -- setting.attr["unset"] = nil
        elseif elem.name == "item" then
            local found = false;
            for child in data:children() do
                -- TODO bare JID or full JID?
                if child.name == elem.name and child.attr["jid"] == elem.attr["jid"] then
                    for k, v in pairs(elem.attr) do
                        child.attr[k] = v;
                    end
                    found = true;
                    break;
                end
            end
            if not found then
                data:tag(elem.name, elem.attr):up();
            end
        elseif elem.name == "session" then
            local found = false;
            for child in data:children() do
                if child.name == elem.name and child.attr["thread"] == elem.attr["thread"] then
                    for k, v in pairs(elem.attr) do
                        child.attr[k] = v;
                    end
                    found = true;
                    break;
                end
            end
            if not found then
                data:tag(elem.name, elem.attr):up();
            end
        elseif elem.name == "method" then
            local newpref = stanza.tags[1]; -- iq:pref
            for _, e in ipairs(newpref.tags) do
                -- if e.name ~= "method" then continue end
                local found = false;
                for child in data:children() do
                    if child.name == "method" and child.attr["type"] == e.attr["type"] then
                        child.attr["use"] = e.attr["use"];
                        found = true;
                        break;
                    end
                end
                if not found then
                    data:tag(e.name, e.attr):up();
                end
            end
        end
        store_prefs(data, node, host);
        origin.send(st.reply(stanza));
        local user = bare_sessions[node.."@"..host];
        local push = st.iq({type="set"});
        push = push:tag('pref', {xmlns='urn:xmpp:archive'});
        if elem.name == "method" then
            for child in data:children() do
                if child.name == "method" then
                    push:add_child(child);
                end
            end
        else
            push:add_child(elem);
        end
        push = push:up();
        for _, res in pairs(user and user.sessions or NULL) do -- broadcast to all resources
            if res.presence then -- to resource
                push.attr.to = res.full_jid;
                res.send(push);
            end
        end
    end
    return true;
end

local function itemremove_handler(event)
    local origin, stanza = event.origin, event.stanza;
    if stanza.attr.type ~= "set" then
        return false;
    end
    local elem = stanza.tags[1].tags[1];
    if not elem or elem.name ~= "item" then
        return false;
    end
    local node, host = origin.username, origin.host;
    local data = load_prefs(node, host);
    if not data then
        return false;
    end
    for i, child in ipairs(data) do
        if child.name == "item" and child.attr["jid"] == elem.attr["jid"] then
            table.remove(data, i)
            break;
        end
    end
    store_prefs(data, node, host);
    origin.send(st.reply(stanza));
    return true;
end

local function sessionremove_handler(event)
    local origin, stanza = event.origin, event.stanza;
    if stanza.attr.type ~= "set" then
        return false;
    end
    local elem = stanza.tags[1].tags[1];
    if not elem or elem.name ~= "session" then
        return false;
    end
    local node, host = origin.username, origin.host;
    local data = load_prefs(node, host);
    if not data then
        return false;
    end
    for i, child in ipairs(data) do
        if child.name == "session" and child.attr["thread"] == elem.attr["thread"] then
            table.remove(data, i)
            break;
        end
    end
    store_prefs(data, node, host);
    origin.send(st.reply(stanza));
    return true;
end

local function auto_handler(event)
    -- event.origin.send(st.error_reply(event.stanza, "cancel", "feature-not-implemented"));
    local origin, stanza = event.origin, event.stanza;
    if stanza.attr.type ~= "set" then
        return false;
    end
    local elem = stanza.tags[1];
    local node, host = origin.username, origin.host;
    local data = load_prefs(node, host);
    if not data then
        return false;
    end
    local setting = data:child_with_name(elem.name)
    for k, v in pairs(elem.attr) do
        setting.attr[k] = v;
    end
    store_prefs(data, node, host);
    origin.send(st.reply(stanza));
    return true;
end

local function chat_handler(event)
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

local function msg_handler(data)
    module:log("debug", "-- Enter msg_handler()");
    local origin, stanza = data.origin, data.stanza;
    module:log("debug", "-- msg:\n%s", tostring(stanza));
    return nil;
end

module:hook("iq/self/urn:xmpp:archive:pref", preferences_handler);
module:hook("iq/self/urn:xmpp:archive:itemremove", itemremove_handler);
module:hook("iq/self/urn:xmpp:archive:sessionremove", sessionremove_handler);
module:hook("iq/self/urn:xmpp:archive:auto", auto_handler);
-- module:hook("iq/self/urn:xmpp:archive:chat", chat_handler);
module:hook("iq/self/urn:xmpp:archive:list", list_handler);
module:hook("iq/self/urn:xmpp:archive:modified", modified_handler);
module:hook("iq/self/urn:xmpp:archive:remove", remove_handler);
module:hook("iq/self/urn:xmpp:archive:retrieve", retrieve_handler);
module:hook("iq/self/urn:xmpp:archive:save", save_handler);

module:hook("message/full", msg_handler, 10);
module:hook("message/bare", msg_handler, 10);

