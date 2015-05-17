# Introduction #

This module implements [XEP-0157: Contact Addresses for XMPP Services](http://xmpp.org/extensions/xep-0157.html).

# Configuration #

```
contact_info = {
	abuse = { "mailto:abuse@shakespeare.lit", "xmpp:abuse@shakespeare.lit" };
	admin = { "mailto:admin@shakespeare.lit", "xmpp:admin@shakespeare.lit" };
	feedback = { "http://shakespeare.lit/feedback.php", "mailto:feedback@shakespeare.lit", "xmpp:feedback@shakespeare.lit" };
	sales = "xmpp:bard@shakespeare.lit";
	security = "xmpp:security@shakespeare.lit";
	support = { "http://shakespeare.lit/support.php", "xmpp:support@shakespeare.lit" };
};
```

The default is based on the `admins` config variable.

# Compatibility #

|trunk|Works|
|:----|:----|