# Introduction #

Registration Redirect as explained in the [IBR XEP](http://xmpp.org/extensions/xep-0077.html#redirect).

# Details #

This module shows instructions on how to register to the server, should it be necessary to perform it through other means Out-Of-Band or not, and also let's registrations origining from ip addresses in the whitelist to go through normally.

# Usage #

Copy the module file into your Prosody modules directory.

The module will work "out of the box" as long as at least an admin entry is specified (see admins = {} option into prosody's documentation).
These are the optional parameters you can specify into your global server/hostname configuration:
```
registration_whitelist = { "*your whitelisted web server ip address*" }
registrarion_url = "*your web registration page url*"
registration_text = "Your custom instructions banner here"
registration_oob = true (default) or false, in the case there's no applicable OOB method (e.g. the server admins needs to be contacted by phone)
```

To not employ any whitelisting (i.e. registration is handled externally).
```
no_registration_whitelist = true
```

# Compatibility #

  * 0.9 works
  * 0.8 works
  * 0.7 might not work
  * 0.6 won't work
  * 0.5 won't work