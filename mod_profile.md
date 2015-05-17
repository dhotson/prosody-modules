# Introduction #

This module provides a replacement for mod\_vcard.  In addition to the ageing protocol defined by [XEP-0054](http://xmpp.org/extensions/xep-0054.html), it also supports the [new vCard 4 based protocol](http://xmpp.org/extensions/xep-0292.html) and integrates with [Personal Eventing Protocol](http://xmpp.org/extensions/xep-0163.html).  The vCard 4, [User Avatar](http://xmpp.org/extensions/xep-0084.html) and [User Nickname](http://xmpp.org/extensions/xep-0172.html) PEP nodes are updated when the vCard is changed..

# Configuration #

```
modules_enabled = {
	-- "pep";   -- These two modules must be removed
	-- "vcard";

	"profile";
}
```


# Compatibility #

Compatible with trunk after 2014-05-29.

It depends on the new mod\_pep\_plus for PEP support.