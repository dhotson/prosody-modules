-- Prosody IM
-- Copyright (C) 2008-2010 Dai Zhiwei
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza";

module:add_feature("urn:xmpp:archive");

local function preferences_handler(event)
    return true;
end

module:hook("iq/self/urn:xmpp:archive:pref", preferences_handler);

