# Introduction #

mod\_proxy65 implements XEP-0065: SOCKS5 Bytestreams as a component. It allows the server to proxy file transfers between 2 clients that are behind NAT routers or firewalls, and otherwise wouldn't be able to transfer files.

# Details #
Once set up, depending on which client you are using the proxy may be automatically used, or the client may have to be configured. Consult your client's friendly documentation for more information :)

# Usage #
```
Component "proxy.example.com" "proxy65"
```

# Configuration #
Although none are required, under the Component section mod\_proxy65 understands several configuration options:

|proxy65\_interface|The server's interface (IP address) to bind (listen) on (default is "`*`", meaning all interfaces)|
|:-----------------|:-------------------------------------------------------------------------------------------------|
|proxy65\_address  |The advertised address of the proxy, which clients use to connect to (default is the same as the hostname of the component)|
|proxy65\_port     |The port on the server to which clients should connect (default is port 5000)                     |
|proxy65\_acl      |Access Control List, when specified all users will be denied access unless in the list. The list can contain domains, bare jids (normal) or full jids (including a resource). e.g. proxy65\_acl = {"example.com", "theadmin@anotherdomain.com", "only@fromwork.de/AtWork"}|

# Compatibility #
|0.7 and above|Officially included in Prosody|
|:------------|:-----------------------------|
|0.6          |Works                         |
|0.5          |Should work                   |

# Todo #
  * Optional support for UDP connections
  * Statistics, bandwidth limits/monitoring