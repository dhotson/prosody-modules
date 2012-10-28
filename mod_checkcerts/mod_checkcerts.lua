local ssl = require"ssl";
local load_cert = ssl.x509 and ssl.x509.load
	or ssl.cert_from_pem; -- COMPAT mw/luasec-hg

if not load_cert then
	module:log("error", "This version of LuaSec (%s) does not support certificate checking", ssl._VERSION);
	return
end

local function check_certs_validity()
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

		local now = os.time();
		local valid_at = cert.valid_at or cert.validat;
		if not valid_at then return end -- Broken or uncommon LuaSec version?

		-- This might be wrong if the certificate has NotBefore in the future.
		-- However this is unlikely to happen in the wild.
		if not valid_at(cert, now) then
			module:log("warn", "The certificate %s has expired", certfile);
		elseif not valid_at(cert, now+86400*7) then
			module:log("warn", "The certificate %s will expire this week", certfile);
		elseif not valid_at(cert, now+86400*30) then
			module:log("info", "The certificate %s will expire later this month", certfile);
		end
		-- TODO Maybe notify admins
	end
end

module.load = check_certs_validity;
module:hook_global("config-reloaded", check_certs_validity);
