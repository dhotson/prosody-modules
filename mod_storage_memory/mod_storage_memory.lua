
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

local stores = {
	keyval = keyval_store;
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
