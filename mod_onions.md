# Introduction #

This plugin allows Prosody to connect to other servers that are running as a Tor hidden service. Running Prosody on a hidden service works without this module, this module is only necessary to allow Prosody to federate to hidden XMPP servers.

For general info about creating a hidden service, see https://www.torproject.org/docs/tor-hidden-service.html.en.

# Usage #
This module depends on the bit32 Lua library.

To create a hidden service that can federate with other hidden XMPP servers, first add a hidden serivce to Tor. It should listen on port 5269 and optionally also on 5222 (if c2s connections to the hidden service should be allowed).

Use the hostname that Tor gives with a virtualhost:

```
VirtualHost "555abcdefhijklmn.onion"
	modules_enabled = { "onions" };
```

# Configuration #
| **Name** | **Description** | **Type** | **Default value** |
|:---------|:----------------|:---------|:------------------|
| onions\_socks5\_host | the host to connect to for Tor's SOCKS5 proxy | string   | "127.0.0.1"       |
| onions\_socks5\_port | the port to connect to for Tor's SOCKS5 proxy | integer  | 9050              |
| onions\_only | forbid all connection attempts to non-onion servers | boolean  | false             |
| onions\_tor\_all | pass all s2s connections through Tor | boolean  | false             |


# Compatibility #
|0.8|Doesn't work|
|:--|:-----------|
|0.9|Works       |

# Security considerations #
  * Running a hidden service on a server together with a normal server might expose the hidden service.
  * A hidden service that wants to remain hidden should either disallow s2s to non-hidden servers or pass all s2s traffic through Tor (setting either `onions_only` or `onions_tor_all`).