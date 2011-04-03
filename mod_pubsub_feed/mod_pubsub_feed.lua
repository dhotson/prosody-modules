-- Fetches Atom feeds and publishes to PubSub nodes
--
-- Depends: http://code.matthewwild.co.uk/lua-feeds
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
--
-- Reference
-- http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html

local modules = hosts[module.host].modules;
if not modules.pubsub then
	--FIXME Should this throw an error() instead?
	module:log("warn", "Pubsub needs to be loaded on this host");
end


local t_insert = table.insert;
local add_task = require "util.timer".add_task;
local date, time = os.date, os.time;
local dt_parse, dt_datetime = require "util.datetime".parse, require "util.datetime".datetime;
local http = require "net.http";
local parse_feed = require "feeds".feed_from_string;
local st = require "util.stanza";
local httpserver = require "net.httpserver";
local formencode = require "net.http".formencode;
local dump = require "util.serialization".serialize;
local uuid = require "util.uuid".generate;
local hmac_sha1 = require "util.hmac".sha1;

local urldecode = require "net.http".urldecode;
local urlencode = require "net.http".urlencode;
local urlparams = --require "net.http".getQueryParams or whatever MattJ names it, FIXME
function(s)
	if not s:match("=") then return urldecode(s); end
	local r = {}
	s:gsub("([^=&]*)=([^&]*)", function(k,v)
		r[ urldecode(k) ] = urldecode(v);
		return nil
	end)
	return r
end;

local config = module:get_option("feeds") or {
	planet_jabber = "http://planet.jabber.org/atom.xml";
	prosody_blog = "http://blog.prosody.im/feed/atom.xml";
};
local refresh_interval = module:get_option_number("feed_pull_interval", 15) * 60;
local use_pubsubhubub = module:get_option_boolean("use_pubsubhubub", true); -- HTTP by default or not?
local feed_list = { }
for node, url in pairs(config) do
	feed_list[node] = { url = url; node = node; last_update = 0 };
end

local response_codes = {
	["200"] = "OK";
	["202"] = "Accepted";
	["400"] = "Bad Request";
	["403"] = "Forbidden";
	["404"] = "Not Found";
	["501"] = "Not Implemented";
};

local function http_response(code, headers, body)
	return {
		status = (type(code) == "number" and code .. " " .. response_codes[tostring(code)]) or code;
		headers = headers or {};
		body = body or "<h1>" .. response_codes[tostring(code)] .. "</h1>\n";
	};
end

local actor = module.host.."/"..module.name;

function update_entry(item)
	local node = item.node;
	--module:log("debug", "parsing %d bytes of data in node %s", #item.data or 0, node)
	local feed = parse_feed(item.data);
	module:log("debug", "updating node %s", node);
	for _, entry in ipairs(feed) do
		entry.attr.xmlns = "http://www.w3.org/2005/Atom";

		local e_published = entry:get_child("published");
		e_published = e_published and e_published:get_text();
		e_published = e_published and dt_parse(e_published);
		local e_updated = entry:get_child("updated");
		e_updated = e_updated and e_updated:get_text();
		e_updated = e_updated and dt_parse(e_updated);

		local timestamp = e_updated or e_published or nil;
		--module:log("debug", "timestamp is %s, item.last_update is %s", tostring(timestamp), tostring(item.last_update));
		if not timestamp or not item.last_update or timestamp > item.last_update then
			local id = entry:get_child("id");
			id = id and id:get_text() or item.url.."#"..dt_datetime(timestamp); -- Missing id, so make one up
			local xitem = st.stanza("item", { id = id }):add_child(entry);
			-- TODO Put data from /feed into item/source

			module:log("debug", "publishing to %s, id %s", node, id);
			local ok, err = modules.pubsub.service:publish(node, actor, id, xitem);
			if not ok then
				if err == "item-not-found" then -- try again
					module:log("debug", "got item-not-found, creating %s and trying again", node);
					local ok, err = modules.pubsub.service:create(node, actor);
					if not ok then
						module:log("error", "could not create node %s: %s", node, err);
						return;
					end
					local ok, err = modules.pubsub.service:publish(node, actor, id, xitem);
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
		module:log("debug", "check if %s has a hub", item.node);
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
		headers["If-Modified-Since"] = date("!%a, %d %b %Y %T %Z", item.last_update);
	end
	http.request(item.url, { headers = headers }, function(data, code, req) 
		if code == 200 then
			item.data = data;
			if callback then callback(item) end
			item.last_update = time();
		end
		if code == 304 then
			item.last_update = time();
		end
	end);
end

function refresh_feeds()
	--module:log("debug", "Refreshing feeds");
	for node, item in pairs(feed_list) do
		--FIXME Don't fetch feeds which have a subscription
		-- Otoho, what if the subscription expires or breaks?
		if item.last_update + refresh_interval < time() then 
			module:log("debug", "checking %s", item.node);
			fetch(item, update_entry);
		end
	end
	return refresh_interval;
end

function subscribe(feed)
	feed.token = uuid();
	feed.secret = uuid();
	local _body, body = {
		["hub.callback"] = "http://"..module.host..":5280/callback?node=" .. urlencode(feed.node); --FIXME figure out your own hostname reliably?
		["hub.mode"] = "subscribe"; --TODO unsubscribe
		["hub.topic"] = feed.url;
		["hub.verify"] = "async";
		["hub.verify_token"] = feed.token;
		["hub.secret"] = feed.secret;
		--["hub.lease_seconds"] = "";
	}, { };
	for name, value in pairs(_body) do
		t_insert(body, { name = name, value = value });
	end --FIXME Why do I have to do this?
	body = formencode(body);

	--module:log("debug", "subscription request, body: %s", body);

	--FIXME The subscription states and related stuff
	feed.subscription = "subscribe";
	http.request(feed.hub, { body = body }, function(data, code, req) 
		local code = tostring(code);
		module:log("debug", "subscription to %s submitted, staus %s", feed.node, code);
	end);
end

function handle_http_request(method, body, request)
	--module:log("debug", "%s request to %s%s with body %s", method, request.url.path, request.url.query and "?" .. request.url.query or "", #body > 0 and body or "empty");
	local query = request.url.query;
	if query and type(query) == "string" then
		query = urlparams(query);
		--module:log("debug", "GET data: %s", dump(query));
	end
	--module:log("debug", "Headers: %s", dump(request.headers));

	if method == "GET" then
		if query.node and feed_list[query.node] then
			local feed = feed_list[query.node];
			if query["hub.topic"] ~= feed.url then
				module:log("debug", "Invalid topic: %s", tostring(query["hub.topic"]))
				return http_response(404)
			end
			if query["hub.mode"] ~= feed.subscription then
				module:log("debug", "Invalid mode: %s", tostring(query["hub.mode"]))
				return http_response(400)
				-- Would this work for unsubscribe?
				-- Also, if feed.subscription is changed here,
				-- it would probably invalidate the subscription
				-- when/if the hub asks if it should be renewed
			end
			if query["hub.verify_token"] ~= feed.token then
				module:log("debug", "Invalid verify_token: %s", tostring(query["hub.verify_token"]))
				return http_response(403)
			end
			module:log("debug", "Confirming %s request to %s", feed.subscription, feed.url)
			return http_response(200, nil, query["hub.challenge"])
		end
		return http_response(400);
	elseif method == "POST" then
		-- TODO http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html#authednotify
		if #body > 0 and feed_list[query.node] then
			module:log("debug", "got %d bytes PuSHed for %s", #body, query.node);
			local feed = feed_list[query.node];
			local signature = request.headers["x-hub-signature"];
			if feed.secret then
				local localsig = "sha1=" .. hmac_sha1(feed.secret, body, true);
				if localsig ~= signature then
					module:log("debug", "Invalid signature");
					return http_response(403);
				end
				module:log("debug", "Valid signature");
			end
			feed.data = body;
			update_entry(feed);
			feed.last_update = time();
			return http_response(202);
		end
		return http_response(400);
	end
	return http_response(501);
end

function init()
	module:log("debug", "initiating", module.name);
	if use_pubsubhubub then
		httpserver.new{ port = 5280, base = "callback", handler = handle_http_request }
	end
	add_task(0, refresh_feeds);
end

if prosody.start_time then -- already started
	init();
else
	prosody.events.add_handler("server-started", init);
end
