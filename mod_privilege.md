# Introduction #

Privileged Entity is an extension which allows entity/component to have privileged access to server (set/get roster, send message on behalf of server, access presence informations). It can be used to build services independently of server (e.g.: PEP service).

# Details #

You can have all the details by reading the [XEP-0356](http://xmpp.org/extensions/xep-0356.html).

If you use it with a component, you need to patch core/mod\_component.lua to fire a new signal. To do it, copy the following patch in a, for example, /tmp/component.patch file:
```
diff --git a/plugins/mod_component.lua b/plugins/mod_component.lua
--- a/plugins/mod_component.lua
+++ b/plugins/mod_component.lua
@@ -85,6 +85,7 @@
                session.type = "component";
                module:log("info", "External component successfully authenticated");
                session.send(st.stanza("handshake"));
+               module:fire_event("component-authenticated", { session = session });
 
                return true;
        end
```

Then, at the root of prosody, enter:

`patch -p1 < /tmp/component.patch`

# Usage #

To use the module, like usual add **"privilege"** to your modules\_enabled. Note that if you use it with a local component, you also need to activate the module in your component section:

```
modules_enabled = {
		[...]
	
		"privilege";
}

[...]

Component "youcomponent.yourdomain.tld"
	component_secret = "yourpassword"
	modules_enabled = {"privilege"}
```

then specify privileged entities **in your host section** like that:

```
VirtualHost "yourdomain.tld"

	privileged_entities = {
		["romeo@montaigu.lit"] = {
			roster = "get";
			presence = "managed_entity";
		},
		["juliet@capulet.lit"] = {
			roster = "both";
			message = "outgoing";
			presence = "roster";
		},
	}
```

Here _romeo@montaigu.lit_ can **get** roster of anybody on the host, and will **have presence for any user** of the host, while _juliet@capulet.lit_ can **get** and **set** a roster, **send messages** on the behalf of the server, and **access presence of anybody linked to the host** (not only people on the server, but also people in rosters of users of the server).

**/!\ Be extra careful when you give a permission to an entity/component, it's a powerful access, only do it if you absoly trust the component/entity, and you know where the software is coming from**

# Configuration #
All the permissions give access to all accounts of the virtual host.
## roster ##
|none _(default)_|No access to rosters|
|:---------------|:-------------------|
|get             |Allow **read** access to rosters|
|set             |Allow **write** access to rosters|
|both            |Allow **read** and **write** access to rosters|

## message ##
|none _(default)_|Can't send message from server|
|:---------------|:-----------------------------|
|outgoing        |Allow to send message on behalf of server (from bare jids)|

## presence ##
|none _(default)_|Do not have extra presence information|
|:---------------|:-------------------------------------|
|managed\_entity |Receive presence stanzas (except subscriptions) from host users|
|roster          |Receive all presence stanzas (except subsciptions) from host users and people in their rosters|

# Compatibility #
|dev|Need a patched core/mod\_component.lua (see above)|
|:--|:-------------------------------------------------|
|0.9|Need a patched core/mod\_component.lua (see above)|

# Note #
This module is often used with mod\_delegation (c.f. XEP for more details)