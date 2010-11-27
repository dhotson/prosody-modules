-- Fetches Atom feeds and publishes to PubSub nodes
--
-- Config:
-- Component "pubsub.example.com" "pubsub"
-- modules_enabled = {
--   "pubsub_feed";
-- }
-- feeds = { -- node -> url
--   prosody_blog = "http://blog.prosody.im/feed/atom.xml";
-- }
-- feed_pull_interval = 20 -- minutes

local modules = hosts[module.host].modules;
if not modules.pubsub then
	module:log("warn", "Pubsub needs to be loaded on this host");
end
local add_task = require "util.timer".add_task;
local date, time = os.date, os.time;
local dt_parse, dt_datetime = require "util.datetime".parse, require "util.datetime".datetime;
local http = require "net.http";
local parse_feed = require "feeds".feed_from_string;
local st = require "util.stanza";

local config = module:get_option("feeds") or {
	planet_jabber = "http://planet.jabber.org/atom.xml";
	prosody_blog = "http://blog.prosody.im/feed/atom.xml";
};
local refresh_interval = (module:get_option("feed_pull_interval") or 15) * 60;
local feed_list = { }
for node, url in pairs(config) do
	feed_list[node] = { url = url };
end

local function update(item, callback)
	local headers = { };
	if item.data and item.last_update then
		headers["If-Modified-Since"] = date("!%a, %d %b %Y %T %Z", item.last_update);
	end
	http.request(item.url, {headers = headers}, function(data, code, req) 
		if code == 200 then
			item.data = data;
			callback(item)
			item.last_update = time();
		end
		if code == 304 then
			item.last_update = time();
		end
	end);
end

local actor = module.host.."/"..module.name;

local function refresh_feeds()
	for node, item in pairs(feed_list) do
		update(item, function(item)
			local feed = parse_feed(item.data);
			module:log("debug", "node: %s", node);
			for _, entry in ipairs(feed) do
				entry.attr.xmlns = "http://www.w3.org/2005/Atom";

				local e_published = entry:get_child("published");
				e_published = e_published and e_published[1];
				e_published = e_published and dt_parse(e_published);
				local e_updated = entry:get_child("updated");
				e_updated = e_updated and e_updated[1];
				e_updated = e_updated and dt_parse(e_updated);

				local timestamp = e_published or e_updated or nil;
				module:log("debug", "timestamp is %s, item.last_update is %s", tostring(timestamp), tostring(item.last_update));
				if not timestamp or not item.last_update or timestamp > item.last_update then
					local id = entry:get_child("id");
					id = id[1] or item.url.."#"..dt_datetime(timestamp); -- Missing id, so make one up
					local item = st.stanza("item", { id = id }):add_child(entry);

					module:log("debug", "publishing to %s, id %s", node, id);
					modules.pubsub.service:publish(node, actor, id, item)
				end
			end
		end);
	end
	return refresh_interval;
end

function init()
	add_task(0, refresh_feeds);
end

if prosody.start_time then -- already started
	init();
else
	prosody.events.add_handler("server-started", init);
end

