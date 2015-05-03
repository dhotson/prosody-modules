module:depends("http");

local st = require "util.stanza";
local json = require "util.json";
local formdecode = require "net.http".formdecode;
local uuid_generate = require "util.uuid".generate;
local timestamp_generate = require "util.datetime".datetime;

local pubsub_service = module:depends("pubsub").service;

function handle_POST(event, path)
	local data = event.request.body;
	local item_id = "default";

	local post_item = st.stanza("item", { id = item_id, xmlns = "http://jabber.org/protocol/pubsub" })
		:tag("entry", { xmlns = "http://www.w3.org/2005/Atom" })
			:tag("id"):text(uuid_generate()):up()
			:tag("title"):text(data):up()
			:tag("author")
				:tag("name"):text(event.request.conn:ip()):up()
				:up()
			:tag("published"):text(timestamp_generate()):up();
	
	local ok, err = pubsub_service:publish(path, true, item_id, post_item);
	module:log("debug", "Handled POST: \n%s\n", tostring(event.request.body));
	return ok and "Posted" or ("Error: "..err);
end

module:provides("http", {
	route = {
		["POST /*"] = handle_POST;
	};
});

function module.load()
	module:log("debug", "Loaded at %s", module:http_url());
end
