-- mod_storage_gdbm
-- Copyright (C) 2014 Kim Alvefur
--
-- This file is MIT/X11 licensed.
-- 
-- Depends on lgdbm:
-- http://webserver2.tecgraf.puc-rio.br/~lhf/ftp/lua/#lgdbm

local gdbm = require"gdbm";
local path = require"util.paths";
local lfs = require"lfs";
local serialize, deserialize = import("util.serialization", "serialize", "deserialize");

local base_path = path.resolve_relative_path(prosody.paths.data, module.host);
lfs.mkdir(base_path);

local cache = {};

local driver = {};
local driver_mt = { __index = driver };

function driver:set(user, value)
	local ok, err = gdbm.replace(self._db, user or "@", serialize(value));
	if not ok then return nil, err; end
	return true;
end

function driver:get(user)
	local data, err = gdbm.fetch(self._db, user or "@");
	if not data then return nil, err; end
	return deserialize(data);
end

function open(_, store, typ)
	typ = typ or "keyval";
	if typ ~= "keyval" then
		return nil, "unsupported-store";
	end

	local db_path = path.join(base_path, store) .. ".db";

	local db = cache[db_path];
	if not db then
		db = assert(gdbm.open(db_path, "c"));
		cache[db_path] = db;
	end
	return setmetatable({ _db = db; _path = db_path; store = store, typ = type }, driver_mt);
end

function module.unload()
	for path, db in pairs(cache) do
		gdbm.sync(db);
		gdbm.close(db);
	end
end

module:provides"storage";
