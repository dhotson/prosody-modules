# Summary #

Sometimes it is useful to get the raw XML logs from clients for debugging purpouses, but some cliens don't expose this.  This command lets you activate this on specific sessions.

# Usage #

In the telnet console:

```
c2s:show()
| example.com
|    user@example.com/bd0b8b19 [c2sb75e93d8] available(0) (encrypted)
|    ...
| OK: Total: $n clients


rawdebug:enable"user@example.com/bd0b8b19"
> OK
```

Then everything sent and received will be logged to debug levels.
