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
local um = require "core.usermanager";
local rom = require "core.rostermanager";

local PREFS_DIR = "archive_muc_prefs";
local ARCHIVE_DIR = "archive_muc";

local AUTO_MUC_ARCHIVING_ENABLED = module:get_option_boolean("auto_muc_archiving_enabled", true);

local NULL = {};

module:add_feature("urn:xmpp:archive#preferences");
module:add_feature("urn:xmpp:archive#management");

------------------------------------------------------------
-- Utils
------------------------------------------------------------
local function trim(s)
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function clean_up(t)
    for i = #t, 1, -1 do
        if type(t[i]) == 'table' then
            clean_up(t[i]);
        elseif type(t[i]) == 'string' and trim(t[i]) == '' then
            table.remove(t, i);
        end
    end
end

local function load_prefs(node, host)
    return st.deserialize(dm.load(node, host, PREFS_DIR));
end

local function store_prefs(data, node, host)
    clean_up(data);
    dm.store(node, host, PREFS_DIR, st.preserialize(data));
end

local date_time = datetime.datetime;

local function match_jid(rule, id)
    return not rule or jid.compare(id, rule);
end

local function is_earlier(start, coll_start)
    return not start or start <= coll_start;
end

local function is_later(endtime, coll_start)
    return not endtime or endtime >= coll_start;
end

------------------------------------------------------------
-- Preferences
------------------------------------------------------------
local function preferences_handler(event)
    local origin, stanza = event.origin, event.stanza;
    module:log("debug", "-- Enter muc preferences_handler()");
    module:log("debug", "-- muc pref:\n%s", tostring(stanza));
    if stanza.attr.type == "get" then
        local data = load_prefs(origin.username, origin.host);
        if data then
            origin.send(st.reply(stanza):add_child(data));
        else
            origin.send(st.reply(stanza));
        end
    elseif stanza.attr.type == "set" then
        local node, host = origin.username, origin.host;
        if stanza.tags[1] and stanza.tags[1].name == 'prefs' then
            store_prefs(stanza.tags[1], node, host);
            origin.send(st.reply(stanza));
            local user = bare_sessions[node.."@"..host];
            local push = st.iq({type="set"});
            push:add_child(stanza.tags[1]);
            for _, res in pairs(user and user.sessions or NULL) do -- broadcast to all resources
                if res.presence then -- to resource
                    push.attr.to = res.full_jid;
                    res.send(push);
                end
            end
        end
    end
    return true;
end

------------------------------------------------------------
-- Archive Management
------------------------------------------------------------
local function management_handler(event)
    module:log("debug", "-- Enter muc management_handler()");
    local origin, stanza = event.origin, event.stanza;
    local node, host = origin.username, origin.host;
	local data = dm.list_load(node, host, ARCHIVE_DIR);
    local elem = stanza.tags[1];
    local resset = {}
    if data then
        for i = #data, 1, -1 do
            local forwarded = st.deserialize(data[i]);
            local res = (match_jid(elem.attr["with"], forwarded.tags[2].attr.from)
                or match_jid(elem.attr["with"], forwarded.tags[2].attr.to))
                and is_earlier(elem.attr["start"], forwarded.tags[1].attr["stamp"])
                and is_later(elem.attr["end"], forwarded.tags[1].attr["stamp"]);
            if res then
                table.insert(resset, forwarded);
            end
        end
        for i = #resset, 1, -1 do
            local res = st.message({to = stanza.attr.from, id=st.new_id()});
            res:add_child(resset[i]);
            origin.send(res);
        end
    end
    origin.send(st.reply(stanza));
    return true;
end

------------------------------------------------------------
-- Message Handler
------------------------------------------------------------
local function is_in(list, jid)
    for _,v in ipairs(list) do
        if match_jid(v:get_text(), jid) then -- JID Matching
            return true;
        end
    end
    return false;
end

local function is_in_roster(node, host, id)
    return rom.is_contact_subscribed(node, host, jid.bare(id));
end

local function apply_pref(node, host, jid)
    local pref = load_prefs(node, host);
    if not pref then
        return AUTO_MUC_ARCHIVING_ENABLED;
    end
    local always = pref:child_with_name('always');
    if always and is_in(always, jid) then
        return true;
    end
    local never = pref:child_with_name('never');
    if never and is_in(never, jid) then
        return false;
    end
    local default = pref.attr['default'];
    if default == 'roster' then
        return is_in_roster(node, host, jid);
    elseif default == 'always' then
        return true;
    elseif default == 'never' then
        return false;
    end
    return AUTO_MUC_ARCHIVING_ENABLED;
end

local function store_msg(msg, node, host)
    local forwarded = st.stanza('forwarded', {xmlns='urn:xmpp:forward:tmp'});
    forwarded:tag('delay', {xmlns='urn:xmpp:delay',stamp=date_time()}):up();
    forwarded:add_child(msg);
    dm.list_append(node, host, ARCHIVE_DIR, st.preserialize(forwarded));
end

local function msg_handler(data)
    module:log("debug", "-- Enter muc msg_handler()");
    local origin, stanza = data.origin, data.stanza;
    local body = stanza:child_with_name("body");
    if body then
        local from_node, from_host = jid.split(stanza.attr.from);
        local to_node, to_host = jid.split(stanza.attr.to);
        if um.user_exists(from_node, from_host) and apply_pref(from_node, from_host, stanza.attr.to) then
            store_msg(stanza, from_node, from_host);
        end
        if um.user_exists(to_node, to_host) and apply_pref(to_node, to_host, stanza.attr.from) then
            store_msg(stanza, to_node, to_host);
        end
    end

    return nil;
end

-- Preferences
module:hook("iq/self/urn:xmpp:archive#preferences:prefs", preferences_handler);
-- Archive management
module:hook("iq/self/urn:xmpp:archive#management:query", management_handler);

module:hook("message/bare", msg_handler, 20);

