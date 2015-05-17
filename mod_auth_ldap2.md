# Introduction #

See [mod\_lib\_ldap](mod_lib_ldap.md) for more information.

# Installation #

You must install [mod\_lib\_ldap](mod_lib_ldap.md) to use this module.  After that, you need only copy mod\_auth\_ldap2.lua to your Prosody installation's plugins directory.

# Configuration #

In addition to the configuration that [mod\_lib\_ldap](mod_lib_ldap.md) itself requires, this plugin also requires the following fields in the ldap section:

  * user.filter
  * admin (optional)

See the README.md distributed with [mod\_lib\_ldap](mod_lib_ldap.md) for details.