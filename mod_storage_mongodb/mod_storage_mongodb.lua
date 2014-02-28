local next = next;
local setmetatable = setmetatable;
local set = require"util.set";
local it = require"util.iterators";
local array = require"util.array";

local params = assert ( module:get_option("mongodb") , "mongodb configuration not found" );

prosody.unlock_globals();
local mongo = require "mongo";
prosody.lock_globals();

local json = require "util.json";

local conn

local keyval_store = {};
keyval_store.__index = keyval_store;

function keyval_store:get(username)
	local host = module.host or "_global";
	local store = self.store;

	-- The database name can't have a period in it (hence it can't be a host/ip)
	local namespace = params.dbname .. "." .. host;
	local v = { _id = { store = store ; username = username } };

	local cursor , err = conn:query ( namespace , v );
	if not cursor then return nil , err end;

	local r , err = cursor:next ( );
	if not r then return nil , err end;
	return r.data;
end

function keyval_store:set(username, data)
	local host = module.host or "_global";
	local store = self.store;

	-- The database name can't have a period in it (hence it can't be a host/ip)
	local namespace = params.dbname .. "." .. host;
	local v = { _id = { store = store ; username = username } };

	if next(data) ~= nil then -- set data
		v.data = data;
		return conn:insert ( namespace , json.encode(v) );
	else -- delete data
		return conn:remove ( namespace , v );
	end;
end

local roster_store = {};
roster_store.__index = roster_store;

function roster_store:get(username)
	local host = module.host or "_global";
	local store = self.store;

	-- The database name can't have a period in it (hence it can't be a host/ip)
	local namespace = params.dbname .. "." .. host;
	local v = { _id = { store = store ; username = username } };

	local cursor , err = conn:query ( namespace , v );
	if not cursor then return nil , err end;

	local r , err = cursor:next ( );
	if not r then return nil , err end;
	local roster = {
		[false] = {
			version = r.version;
		};
		pending = set.new( r.pending )._items;
	};
	local items = r.items;
	for i = 1, #items do
		local item = items[i];
		roster[item.jid] = {
			subscription = item.subscription;
			groups = set.new( item.groups )._items;
			ask = item.ask;
			name = item.name;
		}
	end
	return roster;
end

function roster_store:set(username, data)
	local host = module.host or "_global";
	local store = self.store;

	-- The database name can't have a period in it (hence it can't be a host/ip)
	local namespace = params.dbname .. "." .. host;
	local v = { _id = { store = store ; username = username } };

	if data == nil or next(data) == nil then -- delete data
		return conn:remove ( namespace , v );
	end

	v.version = data[false].version
	if data.pending then
		v.pending = array(it.keys(v.pending))
	end

	local items  = {}
	for jid, item in pairs(data) do
		if jid and jid ~=  "pending" then
			table.insert(items, {
				jid = jid;
				subscription = item.subscription;
				groups = array(it.keys( item.groups ));
				name = item.name;
				ask = item.ask;
			});
		end
	end
	v.items = items;

	return conn:insert ( namespace , v );
end

local driver = {};

function driver:open(store, typ)
	if not conn then
		conn = assert ( mongo.Connection.New ( true ) );
		assert ( conn:connect ( params.server ) );
		if params.username then
			assert ( conn:auth ( params ) );
		end
	end

	if not typ then -- default key-value store
		if store == "roster" then
			return setmetatable({ store = store }, roster_store);
		end
		return setmetatable({ store = store }, keyval_store);
	end;
	return nil, "unsupported-store";
end

module:provides("storage", driver);
