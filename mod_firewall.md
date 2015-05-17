
---


**Note:** mod\_firewall is in its very early stages. This documentation is liable to change, and some described functionality may be missing, incomplete or contain bugs. Feedback is welcome in the comments section at the bottom of this page.


---


# Introduction #

A firewall is an invaluable tool in the sysadmin's toolbox. However while low-level firewalls such as iptables and pf are incredibly good at what they do, they are generally not able to handle application-layer rules.

The goal of mod\_firewall is to provide similar services at the XMPP layer. Based on rule scripts it can efficiently block, bounce, drop, forward, copy, redirect stanzas and more! Furthermore all rules can be applied and updated dynamically at runtime without restarting the server.

# Details #

mod\_firewall loads one or more scripts, and compiles these to Lua code that reacts to stanzas flowing through Prosody. The firewall script syntax is unusual, but straightforward.

A firewall script is dominated by rules. Each rule has two parts: conditions, and actions. When a stanza matches all of the conditions, all of the actions are executed in order.

Here is a simple example to block stanzas from spammer@example.com:

```
FROM: spammer@example.com
DROP.
```

FROM is a condition, and DROP is an action. This is about as simple as it gets. How about heading to the other extreme? Let's demonstrate something more complex that mod\_firewall can do for you:

```
%ZONE myorganisation: staff.myorg.example, support.myorg.example

ENTERING: myorganisation
KIND: message
TIME: 12am-9am, 5pm-12am, Saturday, Sunday
REPLY=Sorry, I am afraid our office is closed at the moment. If you need assistance, please call our 24-hour support line on 123-456-789.
```

This rule will reply with a short message whenever someone tries to send a message to someone at any of the hosts defined in the 'myorganisation' outside of office hours.

Firewall rules should be written to a `ruleset.pfw` file. Multiple such rule
files can be specified in the configuration using:

```
firewall_scripts = { "path/to/ruleset.pfw" }
```

## Conditions ##
All conditions must come before any action in a rule block. The condition name is followed by a colon (':'), and the value to test for.

A condition can be preceded or followed by `NOT` to negate its match. For example:

```
NOT FROM: user@example.com
KIND NOT: message
```

### Zones ###

A 'zone' is one or more hosts or JIDs. It is possible to match when a stanza is entering or leaving a zone, while at the same time not matching traffic passing between JIDs in the same zone.

Zones are defined at the top of a script with the following syntax (they are not part of a rule block):

```
%ZONE myzone: host1, host2, user@host3, foo.bar.example
```

A host listed in a zone also matches all users on that host (but not subdomains).

The following zone-matching conditions are supported:

| **Condition** | **Matches** |
|:--------------|:------------|
| `ENTERING`    | When a stanza is entering the named zone |
| `LEAVING`     | When a stanza is leaving the named zone |

### Stanza matching ###

| **Condition** | **Matches** |
|:--------------|:------------|
| `KIND`        | The kind of stanza. May be 'message', 'presence' or 'iq' |
| `TYPE`        | The type of stanza. This varies depending on the kind of stanza. See 'Stanza types' below for more information. |
| `PAYLOAD`     | The stanza contains a child with the given namespace. Useful for determining the type of an iq request, or whether a message contains a certain extension. |
| `INSPECT`     | The node at the specified path exists or matches a given string. This allows you to look anywhere inside a stanza. See below for examples and more. |

#### Stanza types ####

| **Stanza** | **Valid types** |
|:-----------|:----------------|
| iq         | get, set, result, error |
| presence   | _available_, unavailable, probe, subscribe, subscribed, unsubscribe, unsubscribed, error |
| message    | normal, chat, groupchat, headline, error |

**Note:** The type 'available' for presence does not actually appear in the protocol. Available presence is signalled by the omission of a type. Similarly, a message stanza with no type is equivalent to one of type 'normal'. mod\_firewall handles these cases for you automatically.

#### INSPECT ####

INSPECT takes a 'path' through the stanza to get a string (an attribute value or text content). An example is the best way to explain. Let's check that a user is not trying to register an account with the username 'admin'. This stanza comes from [XEP-0077: In-band Registration](http://xmpp.org/extensions/xep-0077.html#example-4):

```
<iq type='set' id='reg2'>
  <query xmlns='jabber:iq:register'>
    <username>bill</username>
    <password>Calliope</password>
    <email>bard@shakespeare.lit</email>
  </query>
</iq>
```

```
KIND: iq
TYPE: set
PAYLOAD: jabber:iq:register
INSPECT: {jabber:iq:register}query/username#=admin
BOUNCE=not-allowed The username 'admin' is reserved.
```

That weird string deserves some explanation. It is a path, divided into segments by '/'. Each segment describes an element by its name, optionally prefixed by its namespace in curly braces ('{...}'). If the path ends with a '#' then the text content of the last element will be returned. If the path ends with '@name' then the value of the attribute 'name' will be returned.

INSPECT is somewhat slower than the other stanza matching conditions. To minimise performance impact, always place it below other faster condition checks where possible (e.g. above we first checked KIND, TYPE and PAYLOAD matched before INSPECT).

### Sender/recipient matching ###

| **Condition** | **Matches** |
|:--------------|:------------|
| `FROM`        | The JID in the 'from' attribute matches the given JID |
| `TO`          | The JID in the 'to' attribute matches the given JID |

These conditions both accept wildcards in the JID when the wildcard expression is enclosed in angle brackets ('<...>'). For example:

```
# All users at example.com
FROM: <*>@example.com
```
```
# The user 'admin' on any subdomain of example.com
FROM: admin@<*.example.com>
```

You can also use [Lua's pattern matching](http://www.lua.org/manual/5.1/manual.html#5.4.1) for more powerful matching abilities. Patterns are a lightweight regular-expression alternative. Simply contain the pattern in double angle brackets. The pattern is automatically anchored at the start and end (so it must match the entire portion of the JID).

```
# Match admin@example.com, and admin1@example.com, etc.
FROM: <<admin%d*>>@example.com
```

**Note:** It is important to know that 'example.com' is a valid JID on its own, and does **not** match 'user@example.com'. To perform domain whitelists or blacklists, use Zones.

**Note:** Some chains execute before Prosody has performed any normalisation or validity checks on the to/from JIDs on an incoming stanza. It is not advisable to perform access control or similar rules on JIDs in these chains (see the chain documentation for more info).

### Time and date ###
#### TIME ####
Matches stanzas sent during certain time periods.
| **Condition** | **Matches** |
|:--------------|:------------|
| TIME          | When the current server local time is within one of the comma-separated time ranges given |

```
TIME: 10pm-6am, 14:00-15:00
REPLY=Zzzz.
```

#### DAY ####
It is also possible to match only on certain days of the week.

| **Condition** | **Matches** |
|:--------------|:------------|
| DAY           | When the current day matches one, or falls within a rage, in the given comma-separated list of days |

Example:
```
DAY: Sat-Sun, Wednesday
REPLY=Sorry, I'm out enjoying life!
```


### Rate-limiting ###
It is possible to selectively rate-limit stanzas, and use rules to decide what to do with stanzas when over the limit.

First, you must define any rate limits that you are going to use in your script. Here we create a limiter called 'normal' that will allow 2 stanzas per second, and then we define a rule to bounce messages when over this limit. Note that the `RATE` definition is not part of a rule (multiple rules can share the same limiter).

```
%RATE normal: 2 (burst 3)

KIND: message
LIMIT: normal
BOUNCE=policy-violation (Sending too fast!)
```

The 'burst' parameter on the rate limit allows you to spread the limit check over a given time period. For example the definition shown above will allow the limit to be temporarily surpassed, as long as it is within the limit after 3 seconds. You will almost always want to specify a burst factor.

Both the rate and the burst can be fractional values. For example a rate of 0.1 means only one event is allowed every 10 seconds.

The LIMIT condition actually does two things; first it counts against the given limiter, and then it checks to see if the limiter over its limit yet. If it is, the condition matches, otherwise it will not.

| **Condition** | **Matches** |
|:--------------|:------------|
| `LIMIT`       | When the named limit is 'used up'. Using this condition automatically counts against that limit. |

**Note:** Reloading mod\_firewall resets the current state of any limiters.

## Actions ##
Actions come after all conditions in a rule block. There must be at least one action, though conditions are optional.

An action without parameters ends with a full-stop/period ('.'), and one with parameters uses an equals sign ('='):

```
# An action with no parameters:
DROP.

# An action with a parameter:
REPLY=Hello, this is a reply.
```

### Route modification ###
The most common actions modify the stanza's route in some way. Currently the first matching rule to do so will halt further processing of actions and rules (this may change in the future).

| **Action** | **Description** |
|:-----------|:----------------|
| `PASS.`    | Stop executing actions and rules on this stanza, and let it through this chain. |
| `DROP.`    | Stop executing actions and rules on this stanza, and discard it. |
| `REDIRECT=jid` | Redirect the stanza to the given JID. |
| `REPLY=text` | Reply to the stanza (assumed to be a message) with the given text. |
| `BOUNCE.`  | Bounce the stanza with the default error (usually service-unavailable) |
| `BOUNCE=error` | Bounce the stanza with the given error (MUST be a defined XMPP stanza error, see [RFC6120](http://xmpp.org/rfcs/rfc6120.html#stanzas-error-conditions). |
| `BOUNCE=error (text)` | As above, but include the supplied human-readable text with a description of the error |
| `COPY=jid` | Make a copy of the stanza and send the copy to the specified JID. |

### Stanza modification ###
These actions make it possible to modify the content and structure of a stanza.

| **Action** | **Description** |
|:-----------|:----------------|
| `STRIP=name` | Remove any child elements with the given name in the default namespace |
| `STRIP=name namespace` | Remove any child elements with the given name and the given namespace |
| `INJECT=xml` | Inject the given XML into the stanza as a child element |

### Informational ###
| **Action** | **Description** |
|:-----------|:----------------|
| `LOG=message` | Logs the given message to Prosody's log file. Optionally prefix it with a log level in square brackets, e.g. `[debug]`|