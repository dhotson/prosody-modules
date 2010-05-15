

local nodeprep = require "util.encodings".stringprep.nodeprep;
local process = require "process";

local script_type = module:get_option("extauth_type");
assert(script_type == "ejabberd");
local command = module:get_option("extauth_command");
assert(type(command) == "string");
local host = module.host;
assert(not host:find(":"));

local proc;
local function send_query(text)
	if not proc then
		proc = process.popen(command);
	end
	proc:write(text);
	proc:flush();
	return proc:read(4); -- FIXME do properly
end

function do_query(kind, username, password)
	if not username then return nil, "not-acceptable"; end
	username = nodeprep(username);
	if not username then return nil, "jid-malformed"; end
	
	local query = (password and "%s:%s:%s:%s" or "%s:%s:%s"):format(kind, username, host, password);
	local len = #query
	if len > 1000 then return nil, "policy-violation"; end
	
	local lo = len % 256;
	local hi = (len - lo) / 256;
	query = string.char(hi, lo)..query;
	
	local response = send_query(query);
	if response == "\0\2\0\0" then
		return nil, "not-authorized";
	elseif response == "\0\2\0\1" then
		return true;
	else
		proc = nil; -- TODO kill proc
		return nil, "internal-server-error";
	end
end

local provider = { name = "extauth" };

function provider.test_password(username, password)
	return do_query("auth", username, password);
end

function provider.set_password(username, password)
	return do_query("setpass", username, password);
end

function provider.user_exists(username)
	return do_query("isuser", username);
end

function provider.get_password() return nil, "Passwords not available."; end
function provider.create_user(username, password) return nil, "Account creation/modification not available."; end
function provider.get_supported_methods() return {["PLAIN"] = true}; end
local config = require "core.configmanager";
local usermanager = require "core.usermanager";
local jid_bare = require "util.jid".bare;
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


module:add_item("auth-provider", provider);
