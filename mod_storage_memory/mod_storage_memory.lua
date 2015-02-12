
local memory = setmetatable({}, {
	__index = function(t, k)
		local store = module:shared(k)
		t[k] = store;
		return store;
	end
});

local keyval_store = {};
keyval_store.__index = keyval_store;

function keyval_store:get(username)
	return self.store[username];
end

function keyval_store:set(username, data)
	self.store[username] = data;
	return true;
end

local map_store = {};
map_store.__index = map_store;

function map_store:get(username, key)
	local userstore = self.store[username];
	if type(userstore) == "table" then
		return userstore[key];
	end
end

function map_store:set(username, key, data)
	local userstore = self.store[username];
	if userstore == nil then
		userstore = {};
		self.store[username] = userstore;
	end
	userstore[key] = data;
	return true;
end

local stores = {
	keyval = keyval_store;
	map = map_store;
}

local driver = {};

function driver:open(store, typ)
	local store_mt = stores[typ or "keyval"];
	if store_mt then
		return setmetatable({ store = memory[store] }, store_mt);
	end
	return nil, "unsupported-store";
end

module:provides("storage", driver);
