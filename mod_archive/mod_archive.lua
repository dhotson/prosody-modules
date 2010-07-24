-- Prosody IM
-- Copyright (C) 2010 Dai Zhiwei
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza";
local dm = require "util.datamanager";
local jid = require "util.jid";
local datetime = require "util.datetime";

local PREFS_DIR = "archive_prefs";
local ARCHIVE_DIR = "archive";
local xmlns_rsm = "http://jabber.org/protocol/rsm";
local DEFAULT_MAX = 100;

local FORCE_ARCHIVING = false;
local AUTO_ARCHIVING_ENABLED = true;

module:add_feature("urn:xmpp:archive");
module:add_feature("urn:xmpp:archive:auto");
module:add_feature("urn:xmpp:archive:manage");
module:add_feature("urn:xmpp:archive:manual");
module:add_feature("urn:xmpp:archive:pref");
module:add_feature("http://jabber.org/protocol/rsm");

------------------------------------------------------------
-- Utils
------------------------------------------------------------
local function load_prefs(node, host)
    return st.deserialize(dm.load(node, host, PREFS_DIR));
end

local function store_prefs(data, node, host)
    dm.store(node, host, PREFS_DIR, st.preserialize(data));
end

local function os_time()
    -- return tostring(os.time(os.date('!*t')));
    return datetime.datetime();
end

local function date_parse(s)
	local year, month, day, hour, min, sec = s:match("(....)-?(..)-?(..)T(..):(..):(..)Z");
	return os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec});
end

local function store_msg(msg, node, host, isfrom)
    local body = msg:child_with_name("body");
    local thread = msg:child_with_name("thread");
	local data = dm.list_load(node, host, ARCHIVE_DIR);
    local tag = (isfrom and "from") or "to";
    if data then
        for k, v in ipairs(data) do
            local collection = st.deserialize(v);
            if collection.attr["thread"] == thread:get_text() then
                -- TODO figure out secs
                collection:tag(tag, {secs='1', utc=os_time()}):add_child(body);
                local ver = tonumber(collection.attr["version"]) + 1;
                collection.attr["version"] = tostring(ver);
                collection.attr["access"] = os_time();
                data[k] = collection;
                dm.list_store(node, host, ARCHIVE_DIR, st.preserialize(data));
                return;
            end
        end
    end
    -- not found, create new collection
    local utc = os_time();
    local collection = st.stanza('chat', {with = isfrom and msg.attr.to or msg.attr.from, start=utc, thread=thread:get_text(), version='0', access=utc});
    collection:tag(tag, {secs='0', utc=utc}):add_child(body);
    dm.list_append(node, host, ARCHIVE_DIR, st.preserialize(collection));
end

local function save_result(collection)
    local save = st.stanza('save', {xmlns='urn:xmpp:archive'});
    local chat = st.stanza('chat', collection.attr);
    save:add_child(chat);
    return save;
end 

local function gen_uid(c)
    return c.attr["start"] .. c.attr["with"];
end

local function tobool(s)
    if not s then return nil; end
    s = s:lower();
    if s == 'true' or s == '1' then
        return true;
    elseif s == 'false' or s == '0' then
        return false;
    else
        return nil;
    end
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
    -- TODO use 'assert' to check incoming stanza?
    -- or use pcall() to catch exceptions?
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

------------------------------------------------------------
-- Manual Archiving
------------------------------------------------------------
local function save_handler(event)
    local origin, stanza = event.origin, event.stanza;
    if stanza.attr.type ~= "set" then
        return false;
    end
    local elem = stanza.tags[1].tags[1];
    if not elem or elem.name ~= "chat" then
        return false;
    end
    local node, host = origin.username, origin.host;
	local data = dm.list_load(node, host, ARCHIVE_DIR);
    if data then
        for k, v in ipairs(data) do
            local collection = st.deserialize(v);
            if collection.attr["with"] == elem.attr["with"]
                and collection.attr["start"] == elem.attr["start"] then
                -- TODO check if there're duplicates
                for newchild in elem:children() do
                    if type(newchild) == "table" then
                        if newchild.name == "from" or newchild.name == "to" then
                            collection:add_child(newchild);
                        elseif newchild.name == "note" or newchild.name == "previous"
                            or newchild.name == "next" or newchild.name == "x" then
                            local found = false;
                            for i, c in ipairs(collection) do
                                if c.name == newchild.name then
                                    found = true;
                                    collection[i] = newchild;
                                    break;
                                end
                            end
                            if not found then
                                collection:add_child(newchild);
                            end
                        end
                    end
                end
                local ver = tonumber(collection.attr["version"]) + 1;
                collection.attr["version"] = tostring(ver);
                collection.attr["subject"] = elem.attr["subject"];
                collection.attr["access"] = os_time();
                origin.send(st.reply(stanza):add_child(save_result(collection)));
                data[k] = collection;
                dm.list_store(node, host, ARCHIVE_DIR, st.preserialize(data));
                return true;
            end
        end
    end
    -- not found, create new collection
    elem.attr["version"] = "0";
    elem.attr["access"] = os_time();
    origin.send(st.reply(stanza):add_child(save_result(elem)));
    -- TODO check if elem is valid(?)
    dm.list_append(node, host, ARCHIVE_DIR, st.preserialize(elem));
    -- TODO unsuccessful reply
    return true;
end

------------------------------------------------------------
-- Archive Management
------------------------------------------------------------
local function filter_with(with, coll_with)
    return not with or coll_with:find(with);
end

local function filter_start(start, coll_start)
    return not start or start <= coll_start;
end

local function filter_end(endtime, coll_start)
    return not endtime or endtime >= coll_start;
end

local function find_coll(resset, uid)
    for i, c in ipairs(resset) do
        if gen_uid(c) == uid then
            return i;
        end
    end
    return nil;
end

local function list_handler(event)
    local origin, stanza = event.origin, event.stanza;
    local node, host = origin.username, origin.host;
	local data = dm.list_load(node, host, ARCHIVE_DIR);
    local elem = stanza.tags[1];
    local resset = {}
    if data then
        for k, v in ipairs(data) do
            local collection = st.deserialize(v);
            if collection[1] then -- has children(not deleted)
                local res = filter_with(elem.attr["with"], collection.attr["with"]);
                res = res and filter_start(elem.attr["start"], collection.attr["start"]);
                res = res and filter_end(elem.attr["end"], collection.attr["start"]);
                if res then
                    table.insert(resset, collection);
                end
            end
        end
    end
    local reply = st.reply(stanza):tag('list', {xmlns='urn:xmpp:archive'});
    local count = table.getn(resset);
    if count > 0 then
        local max = elem.tags[1]:child_with_name("max");
        if max then
            max = tonumber(max:get_text()) or DEFAULT_MAX;
        else max = DEFAULT_MAX; end
        local after = elem.tags[1]:child_with_name("after");
        local before = elem.tags[1]:child_with_name("before");
        local index = elem.tags[1]:child_with_name("index");
        local s, e = 1, 1+max;
        if after then
            after = after:get_text();
            s = find_coll(resset, after);
            if not s then -- not found
                origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
                return true;
            end
            s = s + 1;
            e = s + max;
        elseif before then
            before = before:get_text();
            if not before or before == '' then -- the last page
                e = count + 1;
                s = e - max;
            else
                e = find_coll(resset, before);
                if not e then -- not found
                    origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
                    return true;
                end
                s = e - max;
            end
        elseif index then
            s = tonumber(index:get_text()) + 1; -- 0-based
            e = s + max;
        end
        if s < 1 then s = 1; end
        if e > count + 1 then e = count + 1; end
        -- Assuming result set is sorted.
        for i = s, e-1 do
            reply:add_child(st.stanza('chat', resset[i].attr));
        end
        local set = st.stanza('set', {xmlns = xmlns_rsm});
        if s <= e-1 then
            set:tag('first', {index=s-1}):text(gen_uid(resset[s])):up()
               :tag('last'):text(gen_uid(resset[e-1])):up();
        end
        set:tag('count'):text(tostring(count)):up();
        reply:add_child(set);
    end
    origin.send(reply);
    return true;
end

local function retrieve_handler(event)
    local origin, stanza = event.origin, event.stanza;
    local node, host = origin.username, origin.host;
	local data = dm.list_load(node, host, ARCHIVE_DIR);
    local elem = stanza.tags[1];
    local collection = nil;
    if data then
        for k, v in ipairs(data) do
            local c = st.deserialize(v);
            if c[1] -- not deleted
                and c.attr["with"] == elem.attr["with"]
                and c.attr["start"] == elem.attr["start"] then
                collection = c;
                break;
            end
        end
    end
    if not collection then
        -- TODO code=404
        origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
        return true;
    end
    local resset = {}
    for i, e in ipairs(collection) do
        if e.name == "from" or e.name == "to" then
            table.insert(resset, e);
        end
    end
    collection.attr['xmlns'] = 'urn:xmpp:archive';
    local reply = st.reply(stanza):tag('chat', collection.attr);
    local count = table.getn(resset);
    if count > 0 then
        local max = elem.tags[1]:child_with_name("max");
        if max then
            max = tonumber(max:get_text()) or DEFAULT_MAX;
        else max = DEFAULT_MAX; end
        local after = elem.tags[1]:child_with_name("after");
        local before = elem.tags[1]:child_with_name("before");
        local index = elem.tags[1]:child_with_name("index");
        local s, e = 1, 1+max;
        if after then
            after = tonumber(after:get_text());
            if not after or after < 1 or after > count then -- not found
                origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
                return true;
            end
            s = after + 1;
            e = s + max;
        elseif before then
            before = tonumber(before:get_text());
            if not before then -- the last page
                e = count + 1;
                s = e - max;
            elseif before < 1 or before > count then
                origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
                return true;
            else
                e = before;
                s = e - max;
            end
        elseif index then
            s = tonumber(index:get_text()) + 1; -- 0-based
            e = s + max;
        end
        if s < 1 then s = 1; end
        if e > count + 1 then e = count + 1; end
        -- Assuming result set is sorted.
        for i = s, e-1 do
            reply:add_child(resset[i]);
        end
        local set = st.stanza('set', {xmlns = xmlns_rsm});
        if s <= e-1 then
            set:tag('first', {index=s-1}):text(tostring(s)):up()
               :tag('last'):text(tostring(e-1)):up();
        end
        set:tag('count'):text(tostring(count)):up();
        reply:add_child(set);
    end
    origin.send(reply);
    return true;
end

local function remove_handler(event)
    local origin, stanza = event.origin, event.stanza;
    local node, host = origin.username, origin.host;
	local data = dm.list_load(node, host, ARCHIVE_DIR);
    local elem = stanza.tags[1];
    if data then
        local count = table.getn(data);
        local found = false;
        for i = count, 1, -1 do
            local collection = st.deserialize(data[i]);
            if collection[1] then -- has children(not deleted)
                local res = filter_with(elem.attr["with"], collection.attr["with"]);
                res = res and filter_start(elem.attr["start"], collection.attr["start"]);
                res = res and filter_end(elem.attr["end"], collection.attr["start"]);
                if res then
                    -- table.remove(data, i);
                    local temp = st.stanza('chat', collection.attr);
                    temp.attr["access"] = os_time();
                    data[i] = temp;
                    found = true;
                end
            end
        end
        if found then
            dm.list_store(node, host, ARCHIVE_DIR, st.preserialize(data));
        else
            origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
            return true;
        end
    end
    origin.send(st.reply(stanza));
    return true;
end

------------------------------------------------------------
-- Replication
------------------------------------------------------------
local function modified_handler(event)
    local origin, stanza = event.origin, event.stanza;
    local node, host = origin.username, origin.host;
	local data = dm.list_load(node, host, ARCHIVE_DIR);
    local elem = stanza.tags[1];
    local resset = {}
    if data then
        for k, v in ipairs(data) do
            local collection = st.deserialize(v);
            local res = filter_start(elem.attr["start"], collection.attr["access"]);
            if res then
                table.insert(resset, collection);
            end
        end
    end
    local reply = st.reply(stanza):tag('modified', {xmlns='urn:xmpp:archive'});
    local count = table.getn(resset);
    if count > 0 then
        local max = elem.tags[1]:child_with_name("max");
        if max then
            max = tonumber(max:get_text()) or DEFAULT_MAX;
        else max = DEFAULT_MAX; end
        local after = elem.tags[1]:child_with_name("after");
        local before = elem.tags[1]:child_with_name("before");
        local index = elem.tags[1]:child_with_name("index");
        local s, e = 1, 1+max;
        if after then
            after = after:get_text();
            s = find_coll(resset, after);
            if not s then -- not found
                origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
                return true;
            end
            s = s + 1;
            e = s + max;
        elseif before then
            before = before:get_text();
            if not before or before == '' then -- the last page
                e = count + 1;
                s = e - max;
            else
                e = find_coll(resset, before);
                if not e then -- not found
                    origin.send(st.error_reply(stanza, "cancel", "item-not-found"));
                    return true;
                end
                s = e - max;
            end
        elseif index then
            s = tonumber(index:get_text()) + 1; -- 0-based
            e = s + max;
        end
        if s < 1 then s = 1; end
        if e > count + 1 then e = count + 1; end
        -- Assuming result set is sorted.
        for i = s, e-1 do
            if resset[i][1] then
                reply:add_child(st.stanza('changed', resset[i].attr));
            else
                reply:add_child(st.stanza('removed', resset[i].attr));
            end
        end
        local set = st.stanza('set', {xmlns = xmlns_rsm});
        if s <= e-1 then
            set:tag('first', {index=s-1}):text(gen_uid(resset[s])):up()
               :tag('last'):text(gen_uid(resset[e-1])):up();
        end
        set:tag('count'):text(tostring(count)):up();
        reply:add_child(set);
    end
    origin.send(reply);
    return true;
end

------------------------------------------------------------
-- Message Handler
------------------------------------------------------------
local function find_pref(pref, name, k, v, exactmatch)
    for i, child in ipairs(pref) do
        if child.name == name then
            if k and v then
                if exactmatch and child.attr[k] == v then
                    return child;
                elseif not exactmatch then
                    if tobool(child.attr['exactmatch']) then
                        if child.attr[k] == v then
                            return child;
                        end
                    elseif filter_with(child.attr[k], v) then
                        return child;
                    end
                end
            else
                return child;
            end
        end
    end
    return nil;
end

local function apply_pref(node, host, jid, thread)
    if FORCE_ARCHIVING then return true; end

    local pref = load_prefs(node, host);
    if not pref then
        return AUTO_ARCHIVING_ENABLED;
    end
    local auto = pref:child_with_name('auto');
    if not tobool(auto.attr['save']) then
        return false;
    end
    if thread then
        local child = find_pref(pref, 'session', 'thread', thread, true);
        if child then
            return tobool(child.attr['save']) ~= false;
        end
    end
    local child = find_pref(pref, 'item', 'jid', jid, false); -- JID Matching
    if child then
        return tobool(child.attr['save']) ~= false;
    end
    local default = pref:child_with_name('default');
    if default then
        return tobool(default.attr['save']) ~= false;
    end
    return AUTO_ARCHIVING_ENABLED;
end

local function msg_handler(data)
    module:log("debug", "-- Enter msg_handler()");
    local origin, stanza = data.origin, data.stanza;
    local body = stanza:child_with_name("body");
    local thread = stanza:child_with_name("thread");
    if body then
        local from_node, from_host = jid.split(stanza.attr.from);
        local to_node, to_host = jid.split(stanza.attr.to);
        -- FIXME only archive messages of users on this host
        if from_host == "localhost" and apply_pref(from_node, from_host, stanza.attr.to, thread) then
            store_msg(stanza, from_node, from_host, true);
        end
        if to_host == "localhost" and apply_pref(to_node, to_host, stanza.attr.from, thread) then
            store_msg(stanza, to_node, to_host, false);
        end
    end

    return nil;
end

-- Preferences
module:hook("iq/self/urn:xmpp:archive:pref", preferences_handler);
module:hook("iq/self/urn:xmpp:archive:itemremove", itemremove_handler);
module:hook("iq/self/urn:xmpp:archive:sessionremove", sessionremove_handler);
module:hook("iq/self/urn:xmpp:archive:auto", auto_handler);
-- Manual archiving
module:hook("iq/self/urn:xmpp:archive:save", save_handler);
-- Archive management
module:hook("iq/self/urn:xmpp:archive:list", list_handler);
module:hook("iq/self/urn:xmpp:archive:retrieve", retrieve_handler);
module:hook("iq/self/urn:xmpp:archive:remove", remove_handler);
-- Replication
module:hook("iq/self/urn:xmpp:archive:modified", modified_handler);

module:hook("message/full", msg_handler, 10);
module:hook("message/bare", msg_handler, 10);

-- FIXME sort collections
-- TODO exactmatch
-- TODO <item/> JID match
-- TODO 'open attr' in removing a collection
