-- Dovecot authentication backend for Prosody
--
-- Copyright (C) 2010 Javier Torres
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
--

local socket_unix = require "socket.unix";
local datamanager = require "util.datamanager";
local log = require "util.logger".init("auth_internal_plain");
local new_sasl = require "util.sasl".new;
local nodeprep = require "util.encodings".stringprep.nodeprep;
local base64 = require "util.encodings".base64;

local prosody = _G.prosody;

function new_default_provider(host)
	local provider = { name = "dovecot" };
	log("debug", "initializing dovecot authentication provider for host '%s'", host);

	function provider.test_password(username, password)
		log("debug", "test password '%s' for user %s at host %s", password, username, module.host);
		
		c = assert(socket.unix());
		assert(c:connect("/var/run/dovecot/auth-login")); -- FIXME: Hardcoded is bad
		
		local pid = "12345"; -- FIXME: this should be an unique number between processes, recommendation is PID

		-- Send our handshake
        -- FIXME: Oh no! There are asserts everywhere
		assert(c:send("VERSION\t1\t1\n"));
		assert(c:send("CPID\t" .. pid .. "\n"));

		-- Check their handshake
		local done = false;
		while (not done) do
			local l = assert(c:receive());
			parts = string.gmatch(l, "[^\t]+");
			first = parts();
			if (first == "VERSION") then
				assert(parts() == "1");
				assert(parts() == "1");
			elseif (first == "MECH") then
				local ok = false;
				for p in parts do
					if p == "PLAIN" then
						ok = true;
					end
				end
				assert(ok);
			elseif (first == "DONE") then
				done = true;
			end
		end

		-- Send auth data
		username = username .. "@" .. module.host; -- FIXME: this is actually a hack for my server
		local b64 = base64.encode(username .. "\0" .. username .. "\0" .. password);
		local id = "54321"; -- FIXME: probably can just be a fixed value if making one request per connection
		assert(c:send("AUTH\t" .. id .. "\tPLAIN\tservice=XMPP\tresp=" .. b64 .. "\n"));
		local l = assert(c:receive());
		assert(c:close());
		local parts = string.gmatch(l, "[^\t]+");

		if (parts() == "OK") then
			return true;
		else
			return nil, "Auth failed. Invalid username or password.";
		end
	end

	function provider.get_password(username)
		return nil, "Cannot get_password in dovecot backend.";
	end
	
	function provider.set_password(username, password)
		return nil, "Cannot set_password in dovecot backend.";
	end

	function provider.user_exists(username)
        --TODO: Send an auth request. If it returns FAIL <id> user=<user> then user exists.
		return nil, "user_exists not yet implemented in dovecot backend.";
	end

	function provider.create_user(username, password)
		return nil, "Cannot create_user in dovecot backend.";
	end

	function provider.get_sasl_handler()
		local realm = module:get_option("sasl_realm") or module.host;
		local getpass_authentication_profile = {
			plain_test = function(username, password, realm)
                                local prepped_username = nodeprep(username);
                                if not prepped_username then
                                        log("debug", "NODEprep failed on username: %s", username);
                                        return "", nil;
                                end
                                return usermanager.test_password(prepped_username, realm, password), true;
                        end
		};
		return new_sasl(realm, getpass_authentication_profile);
	end
	
	return provider;
end

module:add_item("auth-provider", new_default_provider(module.host));

