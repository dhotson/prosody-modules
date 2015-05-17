# Introduction #

This module allows you to authenticate against an Joomla database.

# Configuration #

SQL connection paramaters are identical to those of [SQL storage](https://prosody.im/doc/modules/mod_storage_sql) except for an additional 'prefix' parameter that defaults to 'jos_'._

```
authentication = "joomla"
sql = { -- See documentation for SQL storage
	driver = "MySQL";
	database = "joomla";
	host = "localhost";
	username = "prosody";
	password = "secretpassword";

	prefix = "jos_";
}
```

# Compatibility #

Prosody 0.8+