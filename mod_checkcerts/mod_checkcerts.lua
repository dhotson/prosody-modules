local ssl = require"ssl";
local load_cert = ssl.x509 and ssl.x509.load
	or ssl.cert_from_pem; -- COMPAT mw/luasec-hg
local st = require"util.stanza"

if not load_cert then
	module:log("error", "This version of LuaSec (%s) does not support certificate checking", ssl._VERSION);
	return
end

local last_check = 0;

local function check_certs_validity()
	local now = os.time();

	if last_check > now - 21600 then
		return
	else
		last_check = now;
	end
	-- First, let's find out what certificate this host uses.
	local ssl_config = config.rawget(module.host, "core", "ssl");
	if not ssl_config then
		local base_host = module.host:match("%.(.*)");
		ssl_config = config.get(base_host, "core", "ssl");
	end

	if ssl_config.certificate then
		local certfile = ssl_config.certificate;
		local cert;

		local fh = io.open(certfile); -- Load the file.
		cert = fh and fh:read"*a";
		fh:close();
		cert = cert and load_cert(cert); -- And parse
		if not cert then return end
		-- No error reporting, certmanager should complain already

		local valid_at = cert.valid_at or cert.validat;
		if not valid_at then return end -- Broken or uncommon LuaSec version?

		-- This might be wrong if the certificate has NotBefore in the future.
		-- However this is unlikely to happen with CA-issued certs in the wild.
		local notafter = cert.notafter and cert:notafter();
		if not valid_at(cert, now) then
			module:log("error", "The certificate %s has expired", certfile);
			module:send(st.message({from=module.host,to=admin,type="chat"},("Certificate for host %s has expired!"):format(module.host)));
		elseif not valid_at(cert, now+86400*7) then
			module:log("warn", "The certificate %s will expire %s", certfile, notafter or "this week");
			for _,admin in ipairs(module:get_option_array("admins", {})) do
				module:send(st.message({from=module.host,to=admin,type="chat"},("Certificate for host %s will expire %s!"):format(module.host, notafter or "this week")));
			end
		elseif not valid_at(cert, now+86400*30) then
			module:log("warn", "The certificate %s will expire later this month", certfile);
		else
			module:log("info", "The certificate %s is valid until %s", certfile, notafter or "later");
		end
	end
end

module:hook_global("config-reloaded", check_certs_validity);
module:add_timer(1, function()
	check_certs_validity();
	return math.random(14400, 86400);
end);
