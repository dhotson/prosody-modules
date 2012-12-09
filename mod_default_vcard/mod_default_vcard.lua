local datamanager = require "util.datamanager";
local st = require "util.stanza";
local host = module.host;

module:hook("user-registered", function(event)
	local username = event.username;
	local data = datamanager.load(username, host, "account_details");
	local vcard = datamanager.load(username, host, "vcard");
	--module:log("debug", "Has account details: %s", data and "yes" or "no");
	--module:log("debug", "Has vCard: %s", vcard and "yes" or "no");
	if data and not vcard then
		-- MAYBE
		-- first .. " " .. last
		-- first, last = name:match("^(%w+) (%w+)$")
		local vcard = st.stanza("vCard", { xmlns = "vcard-temp" })
			:tag("VERSION"):text("3.0"):up()
			:tag("N")
				:tag("FAMILY"):text(data.last or ""):up()
				:tag("GIVEN"):text(data.first or ""):up()
			:up()
			:tag("FN"):text(data.name or ""):up()
			:tag("NICKNAME"):text(data.nick or username):up();
		local ok, err = datamanager.store(username, host, "vcard", st.preserialize(vcard));
		if not ok then
			module:log("error", "Couldn't save vCard data, %s", err);
		end
	end
end);
