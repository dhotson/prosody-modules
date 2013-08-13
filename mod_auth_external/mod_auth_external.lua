--
-- Prosody IM
-- Copyright (C) 2010 Waqas Hussain
-- Copyright (C) 2010 Jeff Mitchell
-- Copyright (C) 2013 Mikael Nordfeldth
-- Copyright (C) 2013 Matthew Wild, finally came to fix it all
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local lpty = assert(require "lpty", "mod_auth_external requires lpty: https://code.google.com/p/prosody-modules/wiki/mod_auth_external#Installation");

local log = module._log;
local host = module.host;
local script_type = module:get_option_string("external_auth_protocol", "generic");
assert(script_type == "ejabberd" or script_type == "generic", "Config error: external_auth_protocol must be 'ejabberd' or 'generic'");
local command = module:get_option_string("external_auth_command", "");
local read_timeout = module:get_option_number("external_auth_timeout", 5);
assert(not host:find(":"), "Invalid hostname");
local usermanager = require "core.usermanager";
local jid_bare = require "util.jid".bare;
local new_sasl = require "util.sasl".new;

local pty = lpty.new({ throw_errors = false, no_local_echo = true, use_path = false });

function send_query(text)
	if not pty:hasproc() then
		local status, ret = pty:exitstatus();
		if status and (status ~= "exit" or ret ~= 0) then
			log("warn", "Auth process exited unexpectedly with %s %d, restarting", status, ret or 0);
			return nil;
		end
		local ok, err = pty:startproc(command);
		if not ok then
			log("error", "Failed to start auth process '%s': %s", command, err);
			return nil;
		end
		log("debug", "Started auth process");
	end

	pty:send(text);
	return pty:read(read_timeout);
end

function do_query(kind, username, password)
	if not username then return nil, "not-acceptable"; end
	
	local query = (password and "%s:%s:%s:%s" or "%s:%s:%s"):format(kind, username, host, password);
	local len = #query
	if len > 1000 then return nil, "policy-violation"; end
	
	if script_type == "ejabberd" then
		local lo = len % 256;
		local hi = (len - lo) / 256;
		query = string.char(hi, lo)..query;
	end
	if script_type == "generic" then
		query = query..'\n';
	end
	
	local response = send_query(query);
	if (script_type == "ejabberd" and response == "\0\2\0\0") or
		(script_type == "generic" and response:gsub("\r?\n$", "") == "0") then
			return nil, "not-authorized";
	elseif (script_type == "ejabberd" and response == "\0\2\0\1") or
		(script_type == "generic" and response:gsub("\r?\n$", "") == "1") then
			return true;
	else
		if response then
			log("warn", "Unable to interpret data from auth process, %d bytes beginning with: %s", #response, (response:sub(1,4):gsub(".", function (c)
				return ("%02X "):format(c:byte());
			end)));
		else
			log("warn", "Error while waiting for result from auth process: %s", response or "unknown error");
		end
		return nil, "internal-server-error";
	end
end

local host = module.host;
local provider = {};

function provider.test_password(username, password)
	return do_query("auth", username, password);
end

function provider.set_password(username, password)
	return do_query("setpass", username, password);
end

function provider.user_exists(username)
	return do_query("isuser", username);
end

function provider.create_user(username, password) return nil, "Account creation/modification not available."; end

function provider.get_sasl_handler()
	local testpass_authentication_profile = {
		plain_test = function(sasl, username, password, realm)
			return usermanager.test_password(username, realm, password), true;
		end,
	};
	return new_sasl(host, testpass_authentication_profile);
end

function provider.is_admin(jid)
	local admins = config.get(host, "core", "admins");
	if admins ~= config.get("*", "core", "admins") then
		if type(admins) == "table" then
			jid = jid_bare(jid);
			for _,admin in ipairs(admins) do
				if admin == jid then return true; end
			end
		elseif admins then
			log("error", "Option 'admins' for host '%s' is not a table", host);
		end
	end
	return usermanager.is_admin(jid); -- Test whether it's a global admin instead
end

module:provides("auth", provider);
