-- Changes the process name to 'prosody' rather than 'lua'/'lua5.1'
-- Copyright (C) 2015 Rob Hoelz
--
-- This file is MIT/X11 licensed.

local proctitle = require 'proctitle';

proctitle 'prosody';
