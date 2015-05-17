# Details #

Auto cleans handlers and open unused http ports (only on server\_select) for BOSH/HTTP modules.

# Usage #

Copy both files into prosody's module directory and place 'em into your enabled modules into the configuration file's global section.

Required parameters, example:
```
local bosh_mod_name_ports_conf_var_reference = { { interface = { "127.0.0.1" }, port = 5280 } }
cleanup_http_modules = { ["bosh_mod_name"] = bosh_mod_name_ports_conf_var_reference, ["bosh_mod_name_unreferenced"] = { { interface = { "127.0.0.1" }, port = 5280 } } }
```

You can either reference other local variables present in the configuration (see above, cleanup\_http\_modules needs to be placed after those in that case) or duplicate 'em (see bosh\_mod\_name\_unreferenced).

# Compatibility #

  * 0.9/trunk works
  * 0.8 works