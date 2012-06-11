local ssl = require"ssl";
if not ssl.cert_from_pem then
	module:log("error", "This version of LuaSec (%s) doesn't support certificate checking", ssl._VERSION);
	return
end

local function check_certs_validity()
	local ssl_config = config.rawget(module.host, "core", "ssl");
	if not ssl_config then
		local base_host = module.host:match("%.(.*)");
		ssl_config = config.get(base_host, "core", "ssl");
	end

	if ssl.cert_from_pem and ssl_config.certificate then
		local certfile = ssl_config.certificate;
		local cert;
		local fh, err = io.open(certfile);
		cert = fh and fh:read"*a";
		cert = cert and ssl.cert_from_pem(cert);
		if not cert then return end
		fh:close();

		if not cert:valid_at(os.time()) then
			module:log("warn", "The certificate %s has expired", certfile);
		elseif not cert:valid_at(os.time()+86400*7) then
			module:log("warn", "The certificate %s will expire this week", certfile);
		elseif not cert:valid_at(os.time()+86400*30) then
			module:log("info", "The certificate %s will expire later this month", certfile);
		end
	end
end

module.load = check_certs_validity;
module:hook_global("config-reloaded", check_certs_validity);
