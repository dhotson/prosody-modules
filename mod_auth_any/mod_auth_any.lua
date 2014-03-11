-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local datamanager = require "util.datamanager";
local log = require "util.logger".init("auth_any");
local type = type;
local error = error;
local ipairs = ipairs;
local hashes = require "util.hashes";
local jid_bare = require "util.jid".bare;
local config = require "core.configmanager";
local usermanager = require "core.usermanager";
local new_sasl = require "util.sasl".new;
local nodeprep = require "util.encodings".stringprep.nodeprep;
local hosts = hosts;

local prosody = _G.prosody;

function new_default_provider(host)
	local provider = { name = "any" };
	log("debug", "initializing default authentication provider for host '%s'", host);

	function provider.test_password(username, password)
		return true;
	end

	function provider.set_password(username, password)
		local account = datamanager.load(username, host, "accounts");
		if account then
			account.password = password;
			return datamanager.store(username, host, "accounts", account);
		end
		return nil, "Account not available.";
	end

	function provider.user_exists(username)
		return true;
	end

	function provider.create_user(username, password)
		return datamanager.store(username, host, "accounts", {password = password});
	end

	function provider.delete_user(username)
		return datamanager.store(username, host, "accounts", nil);
	end

	function provider.get_sasl_handler()
		local getpass_authentication_profile = {
			plain_test = function(sasl, username, password, realm)
				return true, true;
			end
		};
		return new_sasl(module.host, getpass_authentication_profile);
	end

	return provider;
end

module:add_item("auth-provider", new_default_provider(module.host));

