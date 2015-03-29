-- This plugin implements http://xmpp.org/extensions/xep-0157.html
local t_insert = table.insert;
local df_new = require "util.dataforms".new;

-- Source: http://xmpp.org/registrar/formtypes.html#http:--jabber.org-network-serverinfo
local valid_types = {
	abuse = true;
	admin = true;
	feedback = true;
	sales = true;
	security = true;
	support = true;
}

local contact_config = module:get_option("contact_info");
if not contact_config then -- we'll use admins from the config as default
	contact_config = { admin = {}; };
	local admins = module:get_option("admins");
	if not admins or #admins == 0 then
		module:log("debug", "No contact_info or admins in config");
		return -- Nothing to attach, so we'll just skip it.
	end
	module:log("debug", "No contact_info in config, using admins as fallback");
	--TODO fetch global admins too?
	for i = 1,#admins do
		t_insert(contact_config.admin, "xmpp:" .. admins[i])
		module:log("debug", "Added %s to admin-addresses", admins[i]);
	end
end
if not next(contact_config) then
	module:log("debug", "No contacts, skipping");
	return -- No use in serving an empty form.
end
local form_layout = {
	{ value = "http://jabber.org/network/serverinfo"; type = "hidden"; name = "FORM_TYPE"; };
};
local form_values = {};

for t,a in pairs(contact_config) do
	if valid_types[t] and a then
		t_insert(form_layout, { name = t .. "-addresses", type = "list-multi" });
		form_values[t .. "-addresses"] = type(a) == "table" and a or {a};
	end
end

module:add_extension(df_new(form_layout):form(form_values, "result"));
