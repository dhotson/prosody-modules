_**Note:** A modified version of this module is available, but is not yet committed here. The plan is to merge them, for more info see [this thread](http://groups.google.com/group/prosody-dev/browse_thread/thread/282e876116ae4177/906121492495ad35#906121492495ad35)._

# Introduction #

This is a Prosody authentication plugin which uses LDAP as the backend.

# Dependecies #

This module depends on [LuaLDAP](http://www.keplerproject.org/lualdap/) for connecting to an LDAP server.

# Configuration #

Copy the module to the prosody modules/plugins directory.

In Prosody's configuration file, under the desired host section, add:
```
	authentication = "ldap"
	ldap_base = "ou=people,dc=example,dc=com"
```

LDAP options are:
| **Name**        | **Description**                                      | **Default value**  |
|:----------------|:-----------------------------------------------------|:-------------------|
| ldap\_server    | Space-separated list of hostnames or IPs, optionally with port numbers (e.g. "localhost:8389") | "localhost"        |
| ldap\_rootdn    | The distinguished name to auth against               | "" (anonymous)     |
| ldap\_password  | Password for rootdn                                  | ""                 |
| ldap\_filter    | Search filter, with $user and $host substituded for user- and hostname | "(uid=$user)"      |
| ldap\_scope     | Search scope. other values: "base" and "subtree"     | "onelevel"         |
| ldap\_tls       | Enable TLS (StartTLS) to connect to LDAP (can be true or false). The non-standard 'LDAPS' protocol is not supported. | false              |
| ldap\_base      | LDAP base directory which stores user accounts       | This is required   |
| ldap\_mode      | How passwords are validated.                         | "bind"             |

**Note:**  lua-ldap reads from /etc/ldap/ldap.conf and other files like
~prosody/.ldaprc if they exist.  Users wanting to use a particular TLS
root certificate can specify it in the normal way using TLS\_CACERT in
the OpenLDAP config file.

# Modes #

The "getpasswd" mode requires plain text access to passwords in LDAP and
feeds them into Prosodys authentication system.  This enables more secure
authentication mechanisms but does not work for all deployments.

The "bind" performs an LDAP bind, does not require plain text access to
passwords but limits you to the PLAIN authentication mechanism.

# Compatibility #

| 0.8 and above | should work |
|:--------------|:------------|