module:depends("http");

local st = require "util.stanza";
local json = require "util.json";
local formdecode = require "net.http".formdecode;
local hmac_md5 = require "util.hashes".hmac_md5;
local st = require "util.stanza";
local json = require "util.json";
local datetime = require "util.datetime".datetime;


local pubsub_service = module:depends("pubsub").service;

local node = module:get_option_string("googlecode_node", "googlecode");
local auth_key = module:get_option_string("googlecode_auth_key");

if not auth_key then
	module:log("warn", "Specify googlecode_auth_key to prevent commit spoofing!");
end

function handle_POST(event)
	local request = event.request;
	local body = request.body;
	
	if auth_key then
		local digest_header = request.headers["google-code-project-hosting-hook-hmac"];
		local digest = hmac_md5(auth_key, body, true);
		if digest ~= digest_header then
			module:log("warn", "Commit POST failed authentication check, sender gave %s, we got %s, body was:\n%s", tostring(digest_header), tostring(digest), tostring(body));
			return "No thanks.";
		end
	end
	
	local data = json.decode(body);
	
	local project = data.project_name or "somewhere";
	for _, rev in ipairs(data.revisions) do
		if rev.url:match("^http://wiki.") then
			local what;
			for _, page in ipairs(rev.added) do
				what = page:match("^/(.-)%.wiki");
				if what then break; end
			end
			if not what then
				for _, page in ipairs(rev.modified) do
					what = page:match("^/(.-)%.wiki");
					if what then break; end
				end
			end
			rev.message = "wiki ("..(what or "unknown page").."): "..rev.message;
		end
		
		local name = rev.author;
		local email = name:match("<([^>]+)>$");
		if email then
			name = name:gsub("%s*<[^>]+>$", "");
		end

		local ok, err = pubsub_service:publish(node, true, project,
			st.stanza("item", { xmlns = "http://jabber.org/protocol/pubsub", id = project })
			:tag("entry", { xmlns = "http://www.w3.org/2005/Atom" })
				:tag("id"):text(tostring(rev.revision)):up()
				:tag("title"):text(rev.message):up()
				:tag("link", { rel = "alternate", href = rev.url }):up()
				:tag("published"):text(datetime(rev.timestamp)):up()
				:tag("author")
					:tag("name"):text(name):up()
					:tag("email"):text(email):up()
					:up()
		);
	end
	module:log("debug", "Handled POST: \n%s\n", tostring(body));
	return "Thank you Google!";
end

module:provides("http", {
	route = {
		POST = handle_POST;
	};
});

function module.load()
	if not pubsub_service.nodes[node] then
		local ok, err = pubsub_service:create(node, true);
		if not ok then
			module:log("error", "Error creating node: %s", err);
		else
			module:log("debug", "Node %q created", node);
		end
	end
end
