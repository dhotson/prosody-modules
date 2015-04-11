
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

local archive_store = {};
archive_store.__index = archive_store;

function archive_store:append(username, key, when, with, value)
	local a = self.store[username];
	if not a then
		a = {};
		self.store[username] = a;
	end
	local i = #a+1;
	local v = { key = key, when = when, with = with, value = value };
	if not key or a[key] then
		key = tostring(a):match"%x+$"..tostring(v):match"%x+$";
		v.key = key;
	end
	a[i] = v;
	a[key] = i;
	return true;
end

local function archive_iter (a, start, stop, step, limit, when_start, when_end, match_with)
	local item, when, with;
	local count = 0;
	coroutine.yield(true); -- Ready
	for i = start, stop, step do
		item = a[i];
		when, with = item.when, item.with;
		if when >= when_start and when_end >= when and (not match_with or match_with == with) then
			coroutine.yield(item.key, item.value, when, with);
			count = count + 1;
			if limit and count >= limit then return end
		end
	end
end

function archive_store:find(username, query)
	local a = self.store[username] or {};
	local start, stop, step = 1, #a, 1;
	local qstart, qend, qwith = -math.huge, math.huge;
	local limit;
	if query then
		module:log("debug", "query included")
		if query.reverse then
			start, stop, step = stop, start, -1;
			if query.before then
				start = a[query.before];
			end
		elseif query.after then
			start = a[query.after];
		end
		limit = query.limit;
		qstart = query.start or qstart;
		qend = query["end"] or qend;
	end
	if not start then return nil, "invalid-key"; end
	local iter = coroutine.wrap(archive_iter);
	iter(a, start, stop, step, limit, qstart, qend, qwith);
	return iter;
end

function archive_store:delete(username, query)
	if not query or next(query) == nil then
		self.store[username] = nil;
		return true;
	end
	local old = self.store[username];
	if not old then return true; end
	local qstart = query.start or -math.huge;
	local qend = query["end"] or math.huge;
	local qwith = query.with;
	local new = {};
	self.store[username] = new;
	local t;
	for i = 1, #old do
		i = old[i];
		t = i.when;
		if not(qstart >= t and qend <= t and (not qwith or i.with == qwith)) then
			self:append(username, i.key, t, i.with, i.value);
		end
	end
	if #new == 0 then
		self.store[username] = nil;
	end
	return true;
end

local stores = {
	keyval = keyval_store;
	map = map_store;
	archive = archive_store;
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
