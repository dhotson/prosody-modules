
local new_sasl = require "util.sasl".new;
local log = require "util.logger".init("auth_ldap");

local ldap_server = module:get_option_string("ldap_server", "localhost");
local ldap_rootdn = module:get_option_string("ldap_rootdn", "");
local ldap_password = module:get_option_string("ldap_password", "");
local ldap_tls = module:get_option_boolean("ldap_tls");
local ldap_scope = module:get_option_string("ldap_scope", "onelevel");
local ldap_filter = module:get_option_string("ldap_filter", "(uid=%s)");
local ldap_base = assert(module:get_option_string("ldap_base"), "ldap_base is a required option for ldap");

local lualdap = require "lualdap";
local ld = assert(lualdap.open_simple(ldap_server, ldap_rootdn, ldap_password, ldap_tls));
module.unload = function() ld:close(); end

local function ldap_filter_escape(s) return (s:gsub("[\\*\\(\\)\\\\%z]", function(c) return ("\\%02x"):format(c:byte()) end)); end

local function get_user(username)
	module:log("debug", "get_user(%q)", username);
	return ld:search({
		base = ldap_base;
		scope = ldap_scope;
		filter = ldap_filter:format(ldap_filter_escape(username));
	})();
end

local provider = {};

function provider.get_password(username)
	local dn, attr = get_user(username);
	if dn and attr then
		return attr.userPassword;
	end
end

function provider.test_password(username, password)
	return provider.get_password(username) == password;
end
function provider.user_exists(username)
	return not not get_user(username);
end
function provider.set_password(username, password)
	local dn, attr = get_user(username);
	if not dn then return nil, attr end
	if attr.password ~= password then
		ld:modify(dn, { '=', userPassword = password });
	end
	return true
end
function provider.create_user(username, password) return nil, "Account creation not available with LDAP."; end

function provider.get_sasl_handler()
	return new_sasl(module.host, {
		plain = function(sasl, username)
			local password = provider.get_password(username);
			if not password then return "", nil; end
			return password, true;
		end
	});
end

module:provides("auth", provider);
