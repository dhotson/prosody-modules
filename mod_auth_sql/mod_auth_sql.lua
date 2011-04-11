-- Simple SQL Authentication module for Prosody IM
-- Copyright (C) 2011 Tomasz Sterna <tomek@xiaoka.com>
--

local log = require "util.logger".init("auth_sql");
local new_sasl = require "util.sasl".new;
local nodeprep = require "util.encodings".stringprep.nodeprep;

local DBI;
local connection;
local host,user,store = module.host;
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
		dbh:autocommit(false); -- don't commit automatically
		connection = dbh;
		return connection;
	end
end

do -- process options to get a db connection
	DBI = require "DBI";

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

function new_default_provider(host)
	local provider = { name = "sql" };
	log("debug", "initializing default authentication provider for host '%s'", host);

	function provider.test_password(username, password)
		log("debug", "test password '%s' for user %s at host %s", password, username, module.host);
		return nil, "Password based auth not supported.";
	end

	function provider.get_password(username)
		log("debug", "get_password for username '%s' at host '%s'", username, module.host);

		local stmt, err = getsql("SELECT `password` FROM `authreg` WHERE `username`=? AND `realm`=?",
			username, module.host);

		local password = nil;
		if stmt ~= nil then
			for row in stmt:rows(true) do
				password = row.password;
			end
		else
			log("error", "QUERY ERROR: %s %s", err, debug.traceback());
			return nil;
		end

		return password;
	end

	function provider.set_password(username, password)
		return nil, "Password based auth not supported.";
	end

	function provider.user_exists(username)
		return nil, "User exist check not supported.";
	end

	function provider.create_user(username, password)
		return nil, "Account creation/modification not supported.";
	end

	function provider.get_sasl_handler()
		local realm = module:get_option("sasl_realm") or module.host;
		local getpass_authentication_profile = {
			plain = function(sasl, username, realm)
				local prepped_username = nodeprep(username);
				if not prepped_username then
					log("debug", "NODEprep failed on username: %s", username);
					return "", nil;
				end
				local password = usermanager.get_password(prepped_username, realm);
				if not password then
					return "", nil;
				end
				return password, true;
			end
		};
		return new_sasl(realm, getpass_authentication_profile);
	end

	return provider;
end

module:add_item("auth-provider", new_default_provider(module.host));

