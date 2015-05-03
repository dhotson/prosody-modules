local dm = require "core.storagemanager".olddm;
local hmac_sha256 = require"util.hashes".hmac_sha256;
local st = require"util.stanza";
local dt = require"util.datetime";
local new_stream = require "util.xmppstream".new;
local empty = {};

local function fallocate(f, offset, len)
	-- This assumes that current position == offset
	local fake_data = (" "):rep(len);
	local ok, msg = f:write(fake_data);
	if not ok then
		return ok, msg;
	end
	f:seek("set", offset);
	return true;
end;
pcall(function()
	local pposix = require "util.pposix";
	fallocate = pposix.fallocate or fallocate;
end);

local archive = {};
local archive_mt = { __index = archive };

function archive:append(username, _, when, with, data)
	if getmetatable(data) ~= st.stanza_mt then
		return nil, "unsupported-datatype";
	end
	username = username or "@";
	data = tostring(data) .. "\n";
	local day = dt.date(when);
	local filename = dm.getpath(username.."@"..day, module.host, self.store, "xml", true);
	local ok, err;
	local f = io.open(filename, "r+");
	if not f then
		f, err = io.open(filename, "w");
		if not f then return nil, err; end
		ok, err = dm.list_append(username, module.host, self.store, day);
		if not ok then return nil, err; end
	end
	local offset = f and f:seek("end");
	ok, err = fallocate(f, offset, #data);
	if not ok then return nil, err; end
	f:seek("set", offset);
	ok, err = f:write(data);
	if not ok then return nil, err; end
	ok, err = f:close();
	if not ok then return nil, err; end
	local id = day .. "-" .. hmac_sha256(username.."@"..day.."+"..offset, data, true):sub(-16);
	ok, err = dm.list_append(username.."@"..day, module.host, self.store, { id = id, when = when, with = with, offset = offset, length = #data });
	if not ok then return nil, err; end
	return id;
end

function archive:find(username, query)
	username = username or "@";
	query = query or empty;

	local result;
	local function cb(_, stanza)
		if result then
			module:log("warn", "Multiple items in chunk");
		end
		result = stanza;
	end

	local stream_sess = { notopen = true };
	local stream = new_stream(stream_sess, { handlestanza = cb, stream_ns = "jabber:client"});
	local dates = dm.list_load(username, module.host, self.store) or empty;
	stream:feed(st.stanza("stream", { xmlns = "jabber:client" }):top_tag());
	stream_sess.notopen = nil;

	local limit = query.limit;
	local start_day, step, last_day = 1, 1, #dates;
	local count = 0;
	local rev = query.reverse;
	local in_range = not (query.after or query.before);
	if query.after or query.start then
		local d = query.after and query.after:sub(1, 10) or dt.date(query.start);
		for i = 1, #dates do
			if dates[i] == d then
				start_day = i; break;
			end
		end
	end
	if query.before or query["end"] then
		local d = query.before and query.before:sub(1, 10) or dt.date(query["end"]);
		for i = #dates, 1, -1 do
			if dates[i] == d then
				last_day = i; break;
			end
		end
	end
	if rev then
		start_day, step, last_day = last_day, -step, start_day;
	end
	local items, xmlfile;
	local first_item, last_item;

	return function ()
		if limit and count >= limit then xmlfile:close() return; end

		for d = start_day, last_day, step do
			if d ~= start_day or not items then
				module:log("debug", "Load items for %s", dates[d]);
				start_day = d;
				items = dm.list_load(username .. "@" .. dates[d], module.host, self.store) or empty;
				if not rev then
					first_item, last_item = 1, #items;
				else
					first_item, last_item = #items, 1;
				end
				local ferr;
				xmlfile, ferr = io.open(dm.getpath(username .. "@" .. dates[d], module.host, self.store, "xml"));
				if not xmlfile then
					module:log("error", "Error: %s", ferr);
					return;
				end
			end

			for i = first_item, last_item, step do
				module:log("debug", "data[%q][%d]", dates[d], i);
				local item = items[i];
				if not item then
					module:log("debug", "data[%q][%d] is nil", dates[d], i);
					break;
				end
				if xmlfile and in_range
				and (not query.with or item.with == query.with)
				and (not query.start or item.when >= query.start)
				and (not query["end"] or item.when <= query["end"]) then
					count = count + 1;
					first_item = i + step;

					xmlfile:seek("set", item.offset);
					local data = xmlfile:read(item.length);
					local ok, err = stream:feed(data);
					if not ok then
						module:log("warn", "Parse error: %s", err);
					end
					if result then
						local stanza = result;
						result = nil;
						return item.id, stanza, item.when, item.with;
					end
				end
				if (rev and item.id == query.after) or
					(not rev and item.id == query.before) then
					in_range = false;
					limit = count;
				end
				if (rev and item.id == query.before) or
					(not rev and item.id == query.after) then
					in_range = true;
				end
			end
		end
		if xmlfile then
			xmlfile:close();
			xmlfile = nil;
		end
	end
end

function archive:delete(username, query)
	username = username or "@";
	query = query or empty;
	if query.with or query.start or query.after then
		return nil, "not-implemented"; -- Only trimming the oldest messages
	end
	local before = query.before or query["end"] or "9999-12-31";
	if type(before) == "number" then before = dt.date(before); else before = before:sub(1, 10); end
	local dates = dm.list_load(username, module.host, self.store) or empty;
	local remaining_dates = {};
	for d = 1, #dates do
		if dates[d] >= before then
			table.insert(remaining_dates, dates[d]);
		end
	end
	table.sort(remaining_dates);
	local ok, err = dm.list_store(username, module.host, self.store, remaining_dates);
	if not ok then return ok, err; end
	for d = 1, #dates do
		if dates[d] < before then
			os.remove(dm.getpath(username .. "@" .. dates[d], module.host, self.store, "list"));
			os.remove(dm.getpath(username .. "@" .. dates[d], module.host, self.store, "xml"));
		end
	end
	return true;
end

local provider = {};
function provider:open(store, typ)
	if typ ~= "archive" then return nil, "unsupported-store"; end
	return setmetatable({ store = store }, archive_mt);
end

module:provides("storage", provider);
