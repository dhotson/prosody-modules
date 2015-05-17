# Introduction #

This module contains administrative commands.

Supported commands are:
  * Add User
  * Delete User
  * End User Session
  * Change User Password
  * Get User Password
  * Get User Roster
  * Get User Statistics
  * Get List of Online Users
  * Send Announcement to Online Users
  * Shut Down Service

The goal is to implement many/all commands described in XEP-0133.

# Usage #

Load mod\_adhoc\_cmd\_admin after [mod\_adhoc](mod_adhoc.md), you can then use the provided adhoc commands from your XEP-0050 compliant client.

# Compatibility #
|0.7|Works|
|:--|:----|
|0.8|Included in Prosody (in mod\_admin\_adhoc)|

# TODO #

  * Add more commands