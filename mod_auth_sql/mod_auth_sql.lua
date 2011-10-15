-- Simple SQL Authentication module for Prosody IM
-- Copyright (C) 2011 Tomasz Sterna <tomek@xiaoka.com>
-- Copyright (C) 2011 Waqas Hussain <waqas20@gmail.com>
--

local log = require "util.logger".init("auth_sql");
local new_sasl = require "util.sasl".new;
local nodeprep = require "util.encodings".stringprep.nodeprep;
local DBI = require "DBI"
local crypt = require "crypt";

local connection;
local params = module:get_option("sql");
local host = module.host;
local realm = module:get_option_string("realm", host);
local mitm_mode = module:get_option_boolean("mitm_mode");

local resolve_relative_path = require "core.configmanager".resolve_relative_path;
local datamanager = require "util.datamanager";

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
	local stmt, err = getsql("SELECT `password` FROM `users` WHERE `email`=?", username .. "@" .. realm);
	if stmt then
		for row in stmt:rows(true) do
			return row.password;
		end
	end
end

provider = { name = "sql" };

function provider.test_password(username, password)
	local local_data = datamanager.load(username, realm, "accounts") or {};
	if data.password == password then return true end
	local dirty;
	local hash = data.crypted_password;
	if not hash then
		hash = get_password(username);
		if hash then
			data.crypted_password = hash;
			dirty = true;
		else
			return false
		end
	end
	local ok = password and crypt(password, hash) == password;
	if ok and mitm_mode then
		local_data.password = password;
		dirty = true
	end
	if dirty then
		datamanager.store(username, realm, "accounts", local_data);
	end
	return ok
end
function provider.get_password(username)
	return nil, "Getting password is not supported.";
end
function provider.set_password(username, password)
	return nil, "Setting password is not supported.";
end
function provider.user_exists(username)
	return datamanager.load(username, realm, "accounts") or get_password(username) and true;
end
function provider.create_user(username, password)
	return nil, "Account creation/modification not supported.";
end
function provider.get_sasl_handler()
	local profile = {
		plain_test = function(sasl, username, password, realm)
			local prepped_username = nodeprep(username);
			if not prepped_username then
				module:log("debug", "NODEprep failed on username: %s", username);
				return nil;
			end
			return provider.test_password(prepped_username, password);
		end
	};
	return new_sasl(host, profile);
end

module:add_item("auth-provider", provider);
