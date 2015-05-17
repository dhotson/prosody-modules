# Introduction #

On some servers, especially public ones, it is desired to make sure that everyone gets their fair share of system resources (and no more).

mod\_limits allows you to specify traffic bandwidth limits, preventing any single connection hogging the server's CPU, RAM and bandwidth.

# Details #

mod\_limits detects when a connection has exceeded its traffic allowance and temporarily ignores a connection. Due to the way TCP and the OS's network API works no data is lost, only slowed.

# Configuration #
Currently mod\_limits is configured per connection type. The possible connection types are:

  * c2s
  * s2sin
  * s2sout
  * component

The limits are specified like so in the **global** section of your config (they cannot be per-host):

```
    limits = {
        c2s = {
            rate = "3kb/s";
            burst = "2s";
        };
        s2sin = {
            rate = "10kb/s";
            burst = "5s";
        };
     }
```

All units are in terms of _bytes_, not _bits_, so that "kb/s" is interpreted as "kilobytes per second", where a kilobyte is 1000 bytes.

# Compatibility #
| 0.9 | Works |
|:----|:------|
| 0.8 | Doesn't work(`*`) |

(`*`) This module can be made to work in 0.8 if you do two things:

  1. Install [util.throttle](http://hg.prosody.im/0.9/raw-file/d46948d3018a/util/throttle.lua) into your Prosody source's util/ directory.
  1. If you use libevent apply [this patch](http://prosody.im/patches/prosody08-mod-limits-fix.patch) to net/server\_event.lua.