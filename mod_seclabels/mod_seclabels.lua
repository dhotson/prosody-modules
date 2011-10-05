local st = require "util.stanza";

local xmlns_label = "urn:xmpp:sec-label:0";
local xmlns_label_catalog = "urn:xmpp:sec-label:catalog:2";
local xmlns_label_catalog_old = "urn:xmpp:sec-label:catalog:0"; -- COMPAT

module:add_feature(xmlns_label);
module:add_feature(xmlns_label_catalog);
module:add_feature(xmlns_label_catalog_old);

module:hook("account-disco-info", function(event) -- COMPAT
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

function handle_catalog_request(request)
	local catalog_request = request.stanza.tags[1];
	local reply = st.reply(request.stanza)
		:tag("catalog", {
			xmlns = catalog_request.attr.xmlns,
			to = catalog_request.attr.to,
			name = catalog_name,
			desc = catalog_desc
		});
	
	local function add_labels(catalog, labels, selector)
		for name, value in pairs(labels) do
			if value.label then
				if catalog_request.attr.xmlns == xmlns_label_catalog then
					catalog:tag("item", {
						selector = selector..name,
						default = value.default and "true" or nil,
					}):tag("securitylabel", { xmlns = xmlns_label })
				else -- COMPAT
					catalog:tag("securitylabel", {
						xmlns = xmlns_label,
						selector = selector..name,
						default = value.default and "true" or nil,
					})
				end
				if value.name or value.color or value.bgcolor then
					catalog:tag("displaymarking", {
						fgcolor = value.color,
						bgcolor = value.bgcolor,
					}):text(value.name or name):up();
				end
				if type(value.label) == "string" then
					catalog:tag("label"):text(value.label):up();
				elseif type(value.label) == "table" then
					catalog:tag("label"):add_child(value.label):up();
				end
				catalog:up();
				if catalog_request.attr.xmlns == xmlns_label_catalog then
					catalog:up();
				end
			else
				add_labels(catalog, value, (selector or "")..name.."|");
			end
		end
	end
	add_labels(reply, labels, "");
	request.origin.send(reply);
	return true;
end
module:hook("iq/host/"..xmlns_label_catalog..":catalog", handle_catalog_request);
module:hook("iq/self/"..xmlns_label_catalog..":catalog", handle_catalog_request); -- COMPAT
module:hook("iq/self/"..xmlns_label_catalog_old..":catalog", handle_catalog_request); -- COMPAT
