# Introduction #

This module implements DANE as described in
[Using DNS Security Extensions (DNSSEC) and DNS-based Authentication of Named Entities (DANE) as a Prooftype for XMPP Domain Name Associations](http://tools.ietf.org/html/draft-miller-xmpp-dnssec-prooftype).

# Dependencies #

This module requires a DNSSEC aware DNS resolver.  Prosodys internal DNS
module does not support DNSSEC.  Therefore, to use this module, a
replacement is needed, such as [this one](https://www.zash.se/luaunbound.html).

More installation instructions can be found at [Prosody with DANE](https://www.zash.se/prosody-dane.html).

# Configuration #

After [installing the module](https://prosody.im/doc/installing_modules), just add it to `modules_enabled`;

```
modules_enabled = {
	...
	"s2s_auth_dane";
}
```

# DNS Setup #

In order for other services to verify your site using using this plugin,
you need to publish TLSA records (and they need to have this plugin).
Here's an example using "DANE-EE Cert SHA2-256" for a host named
xmpp.example.com serving the domain example.com.

```
$ORIGIN example.com.
; Your standard SRV record
_xmpp-server._tcp.example.com IN SRV 0 0 5269 xmpp.example.com.
; IPv4 and IPv6 addresses
xmpp.example.com. IN A 192.0.2.68
xmpp.example.com. IN AAAA 2001:0db8:0000:0000:4441:4e45:544c:5341

; The DANE TLSA records.  These three are equivalent, you would use only one of them.
; First, using symbolic names:
_5269._tcp.xmpp.example.com. 300 IN TLSA DANE-EE Cert SHA2-256 E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
; Using numbers:
_5269._tcp.xmpp.example.com. 300 IN TLSA 3 0 1 E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
; Raw binary format, should work even with very old DNS tools:
_5269._tcp.xmpp.example.com. 300 IN TYPE52 \# 35 030001E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
```

[List of DNSSEC and DANE tools](http://www.internetsociety.org/deploy360/dnssec/tools/)

# Further reading #

**[DANE TLSA implementation and operational guidance](http://tools.ietf.org/html/draft-ietf-dane-ops)**

# Compatibility #

Requires 0.9 or above.