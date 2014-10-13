-- Prosody IM
-- Copyright (C) 2008-2013 Matthew Wild
-- Copyright (C) 2008-2013 Waqas Hussain
-- Copyright (C) 2014 Kim Alvefur
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local usermanager = require "core.usermanager";
local new_sasl = require "util.sasl".new;
local base64 = require "util.encodings".base64.encode;
local waiter =require "util.async".waiter;
local http = require "net.http";

local log = module._log;
local host = module.host;

local api_base = module:get_option_string("http_auth_url",  ""):gsub("$host", host);
if api_base == "" then error("http_auth_url required") end

local provider = {};

function provider.test_password(username, password)
	log("debug", "test password for user %s at host %s", username, host);

	local wait, done = waiter();

	local code = -1;
	http.request(api_base:gsub("$user", username), {
		headers = {
			Authorization = "Basic "..base64(username..":"..password);
		};
	},
	function(body, _code)
		code = _code;
		done();
	end);

	wait();

	if code >= 200 and code <= 299 then
		return true;
	else
		module:log("debug", "HTTP auth provider returned status code %d", code);
		return nil, "Auth failed. Invalid username or password.";
	end
end

function provider.set_password(username, password)
	return nil, "Changing passwords not supported";
end

function provider.user_exists(username)
	return true;
end

function provider.create_user(username, password)
	return nil, "User creation not supported";
end

function provider.delete_user(username)
	return nil , "User deletion not supported";
end

function provider.get_sasl_handler()
	return new_sasl(host, {
		plain_test = function(sasl, username, password, realm)
			return usermanager.test_password(username, realm, password), true;
		end
	});
end
	
module:provides("auth", provider);

