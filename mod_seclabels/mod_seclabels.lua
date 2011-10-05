local st = require "util.stanza";

local xmlns_label = "urn:xmpp:sec-label:0";
local xmlns_label_catalog = "urn:xmpp:sec-label:catalog:0";

module:add_feature(xmlns_label);

module:hook("account-disco-info", function(event)
	local stanza = event.stanza;
	stanza:tag('feature', {var=xmlns_label}):up();
	stanza:tag('feature', {var=xmlns_label_catalog}):up();
end);

local default_labels = {
	Classified = {
		SECRET = { color = "black", bgcolor = "aqua", label = "THISISSECRET" };
		PUBLIC = { label = "THISISPUBLIC" };
	};
};
local catalog_name, catalog_desc, labels;
function get_conf() 
	catalog_name = module:get_option_string("security_catalog_name", "Default");
	catalog_desc = module:get_option_string("security_catalog_desc", "My labels");
	labels = module:get_option("security_labels", default_labels);
end
module:hook("config-reloaded",get_conf);
get_conf();

module:hook("iq/self/"..xmlns_label_catalog..":catalog", function (request)
	local catalog_request = request.stanza.tags[1];
	local reply = st.reply(request.stanza)
		:tag("catalog", {
			xmlns = xmlns_label_catalog,
			to = catalog_request.attr.to,
			name = catalog_name,
			desc = catalog_desc
		});
	
	local function add_labels(catalog, labels, selector)
		for name, value in pairs(labels) do
			if value.label then
				catalog:tag("securitylabel", { xmlns = xmlns_label, selector = selector..name })
						:tag("displaymarking", {
							fgcolor = value.color or "black",
							bgcolor = value.bgcolor or "white",
							}):text(value.name or name):up()
						:tag("label");
				if type(value.label) == "string" then
					catalog:text(value.label);
				else
					catalog:add_child(value.label);
				end
				catalog:up():up();
			else
				add_labels(catalog, value, (selector or "")..name.."|");
			end
		end
	end
	add_labels(reply, labels);
	request.origin.send(reply);
	return true;
end);
