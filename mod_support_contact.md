# Introduction #

This Prosody plugin adds a default contact to newly registered accounts.

# Usage #

Simply add "support\_contact" to your modules\_enabled list. When a new account is created, the new roster would be initialized to include a support contact.

# Configuration #

| support\_contact | The bare JID of the support contact. The default is support@hostname, where hostname is the host the new user's account is on. |
|:-----------------|:-------------------------------------------------------------------------------------------------------------------------------|
| support\_contact\_nick | Nickname of the support contact. The default is "Support".                                                                     |
| support\_contact\_group | The roster group in the support contact's roster in which to add the new user.                                                 |

# Compatibility #
|0.7|Works|
|:--|:----|
|0.6|Works|

# Caveats/Todos/Bugs #

  * This only works for accounts created via in-band registration.