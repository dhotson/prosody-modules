-- phpbb3 authentication backend for Prosody
--
-- Copyright (C) 2011 Waqas Hussain
--

local log = require "util.logger".init("auth_sql");
local new_sasl = require "util.sasl".new;
local nodeprep = require "util.encodings".stringprep.nodeprep;
local DBI = require "DBI"
local md5 = require "util.hashes".md5;

local connection;
local params = module:get_option("sql");

local resolve_relative_path = require "core.configmanager".resolve_relative_path;

local function test_connection()
	if not connection then return nil; end
	if connection:ping() then
		return true;
	else
		module:log("debug", "Database connection closed");
		connection = nil;
	end
end
local function connect()
	if not test_connection() then
		prosody.unlock_globals();
		local dbh, err = DBI.Connect(
			params.driver, params.database,
			params.username, params.password,
			params.host, params.port
		);
		prosody.lock_globals();
		if not dbh then
			module:log("debug", "Database connection failed: %s", tostring(err));
			return nil, err;
		end
		module:log("debug", "Successfully connected to database");
		dbh:autocommit(true); -- don't run in transaction
		connection = dbh;
		return connection;
	end
end

do -- process options to get a db connection
	params = params or { driver = "SQLite3" };
	
	if params.driver == "SQLite3" then
		params.database = resolve_relative_path(prosody.paths.data or ".", params.database or "prosody.sqlite");
	end
	
	assert(params.driver and params.database, "Both the SQL driver and the database need to be specified");
	
	assert(connect());
end

local function getsql(sql, ...)
	if params.driver == "PostgreSQL" then
		sql = sql:gsub("`", "\"");
	end
	if not test_connection() then connect(); end
	-- do prepared statement stuff
	local stmt, err = connection:prepare(sql);
	if not stmt and not test_connection() then error("connection failed"); end
	if not stmt then module:log("error", "QUERY FAILED: %s %s", err, debug.traceback()); return nil, err; end
	-- run query
	local ok, err = stmt:execute(...);
	if not ok and not test_connection() then error("connection failed"); end
	if not ok then return nil, err; end
	
	return stmt;
end

local function get_password(username)
	local stmt, err = getsql("SELECT `user_password` FROM `phpbb_users` WHERE `username`=?", username);
	if stmt then
		for row in stmt:rows(true) do
			return row.user_password;
		end
	end
end

local itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

local function hashEncode64(input)
	local count = 16;
	local output = "";
	local i, value = 0, 0;

	while true do
		value = input:byte(i+1)
		i = i+1;
		local idx = value % 0x40 + 1;
		output = output .. itoa64:sub(idx, idx);

		if i < count then
			value = value + input:byte(i+1) * 256;
		end
		local _ = value % (2^6);
		local idx = ((value - _) / (2^6)) % 0x40 + 1
		output = output .. itoa64:sub(idx, idx);

		if i >= count then break; end
		i = i+1;

		if i < count then
			value = value + input:byte(i+1) * 256 * 256;
		end
		local _ = value % (2^12);
		local idx = ((value - _) / (2^12)) % 0x40 + 1
		output = output .. itoa64:sub(idx, idx);

		if i >= count then break; end
		i = i+1;

		local _ = value % (2^18);
		local idx = ((value - _) / (2^18)) % 0x40 + 1
		output = output .. itoa64:sub(idx, idx);

		if not(i < count) then break; end
	end
	return output;
end
local function hashCryptPrivate(password, genSalt, itoa64)
	local output = "*";
	if not genSalt:match("^%$H%$") then return output; end

	local count_log2 = itoa64:find(genSalt:sub(4,4)) - 1;
	if count_log2 < 7 or count_log2 > 30 then return output; end

	local count = 2 ^ count_log2;
	local salt = genSalt:sub(5, 12);

	if #salt ~= 8 then return output; end

	local hash = md5(salt..password);

	while true do
		hash = md5(hash..password);
		if not(count > 1) then break; end
		count = count-1;
	end

	output = genSalt:sub(1, 12);
	output = output .. hashEncode64(hash);

	return output;
end
local function phpbbCheckHash(password, hash)
	return #hash == 34 and hashCryptPrivate(password, hash, itoa64) == hash;
end

provider = { name = "phpbb3" };

function provider.test_password(username, password)
	module:log("debug", "test_password '%s' for user %s", password, username);

	local hash = get_password(username);
	return phpbbCheckHash(password, hash);
end
function provider.user_exists(username)
	module:log("debug", "test user %s existence", username);
	return get_password(username) and true;
end

function provider.get_password(username)
	return nil, "Getting password is not supported.";
end
function provider.set_password(username, password)
	return nil, "Setting password is not supported.";
end
function provider.create_user(username, password)
	return nil, "Account creation/modification not supported.";
end

function provider.get_sasl_handler()
	local profile = {
		plain_test = function(username, password, realm)
			-- TODO stringprep
			return provider.test_password(username, password), true;
		end;
	};
	return new_sasl(module.host, profile);
end

module:add_item("auth-provider", provider);

