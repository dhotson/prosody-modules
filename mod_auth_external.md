# Introduction #

Allow client authentication to be handled by an external script/process.

# Installation #

mod\_auth\_external depends on a Lua module called [lpty](http://www.tset.de/lpty/). You can install it on many platforms using [LuaRocks](http://luarocks.org/), for example:

```
   sudo luarocks install lpty
```

Note: Earlier versions of the module did not depend on lpty. While using the newer version is strongly recommended, you can find the [older version here](https://prosody-modules.googlecode.com/hg-history/50ee38e95e754bf1034d980364f93564028b2f34/mod_auth_external/mod_auth_external.lua) if you need it (revision 50ee38e95e75 of the repository).

# Configuration #

As with all auth modules, there is no need to add this to modules\_enabled. Simply add in the global section, or for the relevant hosts:

```
    authentication = "external"
```

These options are specific to mod\_auth\_external:

|external\_auth\_protocol|May be "generic" or "ejabberd" (the latter for compatibility with ejabberd external auth scripts. Default is "generic".|
|:-----------------------|:----------------------------------------------------------------------------------------------------------------------|
|external\_auth\_command |The command/script to execute.                                                                                         |

Two other options are also available, depending on whether the module is running in 'blocking' or 'non-blocking' mode:
|external\_auth\_timeout|blocking|The number of seconds to wait for a response from the auth process. Default is 5.|
|:----------------------|:-------|:--------------------------------------------------------------------------------|
|external\_auth\_processes|non-blocking|The number of concurrent processes to spawn. Default is 1, increase to handle high connection rates efficiently.|

## Blocking vs non-blocking ##

Non-blocking mode is automatically activated when:

  * Running Prosody trunk ([nightly](http://prosody.im/nightly/) build 414+).
  * [libevent](http://prosody.im/doc/libevent) is enabled in the config, and LuaEvent is available.
  * lpty (see installation above) is version 1.0.1 or later.

# Protocol #

Prosody executes the given command/script, and sends it queries.

Your auth script should simply read a line from standard input, and write the result to standard output.
It must do this in a loop, until there's nothing left to read. Prosody can keep sending more lines to the script,
with a command on each line.

Each command is one line, and the response is expected to be a single line containing "0" for failure or "1" for success.
Your script must respond with "0" for anything it doesn't understand.

There are three commands used at the moment:

## auth ##
Check if a user's password is valid.

Example: `auth:username:example.com:abc123`

Note: The password can contain colons. Make sure to handle that.

## isuser ##
Check if a user exists.

Example: `isuser:username:example.com`

## setpass ##
Set a new password for the user. Implementing this is optional.

Example: `setpass:username:example.com:abc123`

Note: The password can contain colons. Make sure to handle that.

## ejabberd compatibilty ##
ejabberd implements a similar protocol. The main difference is that Prosody's protocol is line-based, while ejabberd's is length-prefixed.

Add this to your config if you need to use an ejabberd auth script:
```
	external_auth_protocol = "ejabberd"
```

# Compatibility #
|0.8|Works|
|:--|:----|
|0.9|Works|