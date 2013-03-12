
local new_sasl = require "util.sasl".new;
local log = require "util.logger".init("auth_ldap");

local ldap_server = module:get_option("ldap_server") or "localhost";
local ldap_rootdn = module:get_option("ldap_rootdn") or "";
local ldap_password = module:get_option("ldap_password") or "";
local ldap_tls = module:get_option("ldap_tls");
local ldap_base = assert(module:get_option("ldap_base"), "ldap_base is a required option for ldap");

local lualdap = require "lualdap";
local ld = assert(lualdap.open_simple(ldap_server, ldap_rootdn, ldap_password, ldap_tls));
module.unload = function() ld:close(); end

function do_query(query)
	for dn, attribs in ld:search(query) do
		return true; -- found a result
	end
end

local provider = {};

local function ldap_filter_escape(s) return (s:gsub("[\\*\\(\\)\\\\%z]", function(c) return ("\\%02x"):format(c:byte()) end)); end
function provider.test_password(username, password)
	return do_query({
		base = ldap_base;
		filter = "(&(uid="..ldap_filter_escape(username)..")(userPassword="..ldap_filter_escape(password)..")(accountStatus=active))";
	});
end
function provider.user_exists(username)
	return do_query({
		base = ldap_base;
		filter = "(uid="..ldap_filter_escape(username)..")";
	});
end

function provider.get_password(username) return nil, "Passwords unavailable for LDAP."; end
function provider.set_password(username, password) return nil, "Passwords unavailable for LDAP."; end
function provider.create_user(username, password) return nil, "Account creation/modification not available with LDAP."; end

function provider.get_sasl_handler()
	local testpass_authentication_profile = {
		plain_test = function(sasl, username, password, realm)
			return provider.test_password(username, password), true;
		end
	};
	return new_sasl(module.host, testpass_authentication_profile);
end

module:provides("auth", provider);
