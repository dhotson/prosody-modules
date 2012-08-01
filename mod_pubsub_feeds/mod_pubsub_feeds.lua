-- Fetches Atom feeds and publishes to PubSub nodes
--
-- Depends: http://code.matthewwild.co.uk/lua-feeds
--
-- Config:
-- Component "pubsub.example.com" "pubsub"
-- modules_enabled = {
--   "pubsub_feeds";
-- }
-- feeds = { -- node -> url
--   prosody_blog = "http://blog.prosody.im/feed/atom.xml";
-- }
-- feed_pull_interval = 20 -- minutes
--
-- Reference
-- http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html

local modules = hosts[module.host].modules;
if not modules.pubsub or module:get_option("component_module") ~= "pubsub" then
	module:log("warn", "Pubsub needs to be loaded on this host");
	--module:log("debug", "component_module is %s", tostring(module:get_option("component_module")));
	return
end

local date, time = os.date, os.time;
local dt_parse, dt_datetime = require "util.datetime".parse, require "util.datetime".datetime;
local uuid = require "util.uuid".generate;
local hmac_sha1 = require "util.hmac".sha1;
local parse_feed = require "feeds".feed_from_string;
local st = require "util.stanza";
--local dump = require"util.serialization".serialize;

local xmlns_atom = "http://www.w3.org/2005/Atom";

local use_pubsubhubub = module:get_option_boolean("use_pubsubhubub", true);
if use_pubsubhubub then
	module:depends"http";
end

local http = require "net.http";
local formdecode = http.formdecode;
local formencode = http.formencode;
local urldecode  = http.urldecode;
local urlencode  = http.urlencode;

local feed_list = module:shared("feed_list");
local refresh_interval;

-- Dynamically reloadable config.
local function update_config()
	local config = module:get_option("feeds") or {
		planet_jabber = "http://planet.jabber.org/atom.xml";
		prosody_blog = "http://blog.prosody.im/feed/atom.xml";
	};
	refresh_interval = module:get_option_number("feed_pull_interval", 15) * 60;
	local new_feed_list = {};
	for node, url in pairs(config) do
		new_feed_list[node] = true;
		if not feed_list[node] then
			feed_list[node] = { url = url; node = node; last_update = 0 };
		else
			feed_list[node].url = url;
		end
	end
	for node in pairs(feed_list) do
		if not new_feed_list[node] then
			feed_list[node] = nil;
		end
	end
end
update_config();
module:hook_global("config-reloaded", update_config);

function update_entry(item)
	local node = item.node;
	module:log("debug", "parsing %d bytes of data in node %s", #item.data or 0, node)
	local feed = parse_feed(item.data);
	for _, entry in ipairs(feed) do
		entry.attr.xmlns = xmlns_atom;

		local e_published = entry:get_child_text("published");
		e_published = e_published and dt_parse(e_published);
		local e_updated = entry:get_child_text("updated");
		e_updated = e_updated and dt_parse(e_updated);

		local timestamp = e_updated or e_published or nil;
		--module:log("debug", "timestamp is %s, item.last_update is %s", tostring(timestamp), tostring(item.last_update));
		if not timestamp or not item.last_update or timestamp > item.last_update then
			local id = entry:get_child_text("id");
			id = id or item.url.."#"..dt_datetime(timestamp); -- Missing id, so make one up
			local xitem = st.stanza("item", { id = id }):add_child(entry);
			-- TODO Put data from /feed into item/source

			--module:log("debug", "publishing to %s, id %s", node, id);
			local ok, err = modules.pubsub.service:publish(node, true, id, xitem);
			if not ok then
				if err == "item-not-found" then -- try again
					--module:log("debug", "got item-not-found, creating %s and trying again", node);
					local ok, err = modules.pubsub.service:create(node, true);
					if not ok then
						module:log("error", "could not create node %s: %s", node, err);
						return;
					end
					local ok, err = modules.pubsub.service:publish(node, true, id, xitem);
					if not ok then
						module:log("error", "could not create or publish node %s: %s", node, err);
						return
					end
				else
					module:log("error", "publishing %s failed: %s", node, err);
				end
			end
		end
	end
	
	if use_pubsubhubub and not item.subscription then
		--module:log("debug", "check if %s has a hub", item.node);
		local hub = feed.links and feed.links.hub;
		if hub then
			item.hub = hub;
			module:log("debug", "%s has a hub: %s", item.node, item.hub);
			subscribe(item);
		end
	end
end

function fetch(item, callback) -- HTTP Pull
	local headers = { };
	if item.data and item.last_update then
		headers["If-Modified-Since"] = date("!%a, %d %b %Y %H:%M:%S %Z", item.last_update);
	end
	http.request(item.url, { headers = headers }, function(data, code, req) 
		if code == 200 then
			item.data = data;
			if callback then callback(item) end
			item.last_update = time();
		elseif code == 304 then
			item.last_update = time();
		end
	end);
end

function refresh_feeds()
	local now = time();
	--module:log("debug", "Refreshing feeds");
	for node, item in pairs(feed_list) do
		--FIXME Don't fetch feeds which have a subscription
		-- Otoho, what if the subscription expires or breaks?
		if item.last_update + refresh_interval < now then 
			--module:log("debug", "checking %s", item.node);
			fetch(item, update_entry);
		end
	end
	return refresh_interval;
end

local function format_url(node)
	return module:http_url(nil, "/callback") .. "?node=" .. urlencode(node);
end	

function subscribe(feed, want)
	want = want or "subscribe";
	feed.token = uuid();
	feed.secret = feed.secret or uuid();
	local body = formencode{
		["hub.callback"] = format_url(feed.node);
		["hub.mode"] = want;
		["hub.topic"] = feed.url;
		["hub.verify"] = "async";
		["hub.verify_token"] = feed.token;
		["hub.secret"] = feed.secret;
		--["hub.lease_seconds"] = "";
	};

	--module:log("debug", "subscription request, body: %s", body);

	--FIXME The subscription states and related stuff
	feed.subscription = want;
	http.request(feed.hub, { body = body }, function(data, code, req) 
		module:log("debug", "subscription to %s submitted, status %s", feed.node, tostring(code));
		if code >= 400 then
			module:log("error", "There was something wrong with our subscription request, body: %s", tostring(data));
			feed.subscription = "failed";
		end
	end);
end

function handle_http_request(event)
	local request = event.request;
	local method = request.method;
	local body = request.body;

	--module:log("debug", "%s request to %s%s with body %s", method, request.url.path, request.url.query and "?" .. request.url.query or "", #body > 0 and body or "empty");
	local query = request.url.query or {}; --FIXME
	if query and type(query) == "string" then
		query = formdecode(query);
		--module:log("debug", "GET data: %s", dump(query));
	end
	--module:log("debug", "Headers: %s", dump(request.headers));

	local feed = feed_list[query.node];
	if not feed then
		return 404;
	end

	if method == "GET" then
		if query.node then
			if query["hub.topic"] ~= feed.url then
				module:log("debug", "Invalid topic: %s", tostring(query["hub.topic"]))
				return 404
			end
			if query["hub.mode"] ~= feed.subscription then
				module:log("debug", "Invalid mode: %s", tostring(query["hub.mode"]))
				return 400
				-- Would this work for unsubscribe?
				-- Also, if feed.subscription is changed here,
				-- it would probably invalidate the subscription
				-- when/if the hub asks if it should be renewed
			end
			if query["hub.verify_token"] ~= feed.token then
				module:log("debug", "Invalid verify_token: %s", tostring(query["hub.verify_token"]))
				return 401;
			end
			module:log("debug", "Confirming %s request to %s", feed.subscription, feed.url)
			return query["hub.challenge"];
		end
		return 400;
	elseif method == "POST" then
		if #body > 0 then
			module:log("debug", "got %d bytes PuSHed for %s", #body, query.node);
			local signature = request.headers.x_hub_signature;
			if feed.secret then
				local localsig = "sha1=" .. hmac_sha1(feed.secret, body, true);
				if localsig ~= signature then
					module:log("debug", "Invalid signature, got %s but wanted %s", tostring(signature), tostring(localsig));
					return 401;
				end
				module:log("debug", "Valid signature");
			end
			feed.data = body;
			update_entry(feed);
			feed.last_update = time();
			return 202;
		end
		return 400;
	end
	return 501;
end

if use_pubsubhubub then
	module:provides("http", {
		default_path = "/callback";
		route = {
			GET = handle_http_request;
			POST = handle_http_request;
			-- This all?
		};
	});
end

module:add_timer(1, refresh_feeds);
