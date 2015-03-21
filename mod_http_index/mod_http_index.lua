local st = require "util.stanza";
local url = require"socket.url";

module:depends"http";

-- local dump = require"util.serialization".new"dump".serialize;

local function template(data)
	--[[ DOC
	Like util.template, but deals with plain text
	Returns a closure that is called with a table of values
	{name} is substituted for values["name"] and is XML escaped
	{name!} is substituted without XML escaping
	{name?} is optional and is replaced with an empty string if no value exists
	]]
	return function(values)
		return (data:gsub("{([^}]-)(%p?)}", function (name, opt)
			local value = values[name];
			if value then
				if opt ~= "!" then
					return st.xml_escape(value);
				end
				return value;
			elseif opt == "?" then
				return "";
			end
		end));
	end
end

-- TODO Move templates into files
local base = template(template[[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" value="prosody/{prosody_version} mod_{mod_name}">
<link rel="canonical" href="{canonical}">
<title>{title}</title>
<style>
body{background-color:#eeeeec;margin:1ex 0;padding-bottom:3em;font-family:Arial,Helvetica,sans-serif;}
header,footer{margin:1ex 1em;}
footer{font-size:smaller;color:#babdb6;}
.content{background-color:white;padding:1em;list-style-position:inside;}
nav{font-size:large;margin:1ex 1ex;clear:both;line-height:1.5em;}
nav a{padding: 1ex;text-decoration:none;}
nav a[rel="up"]{font-size:smaller;}
nav a[rel="prev"]{float:left;}
nav a[rel="next"]{float:right;}
nav a[rel="next::after"]{content:" →";}
nav a[rel="prev::before"]{content:"← ";}
nav a:empty::after,nav a:empty::before{content:""}
@media screen and (min-width: 460px) {
nav{font-size:x-large;margin:1ex 1em;}
}
a:link,a:visited{color:#2e3436;text-decoration:none;}
a:link:hover,a:visited:hover{color:#3465a4;}
ul,ol{padding:0;}
li{list-style:none;}
hr{visibility:hidden;clear:both;}
br{clear:both;}
li time{float:right;font-size:small;opacity:0.2;}
li:hover time{opacity:1;}
.room-list .description{font-size:smaller;}
q.body::before,q.body::after{content:"";}
.presence .verb{font-style:normal;color:#30c030;}
.presence.unavailable .verb{color:#c03030;}
</style>
</head>
<body>
<header>
<h1>{title}</h1>
{header!}
</header>
<hr>
<div class="content">
{body!}
</div>
<hr>
<footer>
{footer!}
<br>
<div class="powered-by">Prosody {prosody_version?}</div>
</footer>
</body>
</html>
]] { prosody_version = prosody.version, mod_name = module.name });

local canonical = module:http_url(nil, "/");
local page_template = template(base{
	canonical = canonical;
	title = "HTTP stuff";
	header = "";
	body = [[
<nav>
<ul>
{lines!}
</ul>
</nav>
]];
	footer = "";
});
local line_template = template[[
<li><a href="{url}" title="{module}">{name}</a></li>
]];

local function relative(base, link)
	base = url.parse(base);
	link = url.parse(link);
	for k,v in pairs(base) do
		if link[k] == v then
			link[k] = nil;
		end
	end
	return url.build(link);
end

local function handler(event)
	local items = module:get_host_items("http-provider");
	local item;
	for i = 1, #items do
		item = items[i];
		if module.name ~= item._provided_by then
			items[i] = line_template{
				name = item.name;
				module = "mod_" .. item._provided_by;
				url = relative(canonical, module:http_url(item.name, item.default_path));
			};
		else
			items[i] = "";
		end
	end
	event.response.headers.content_type = "text/html";
	return page_template{
		lines = table.concat(items);
	};
end

module:provides("http", {
	route = {
		["GET /"] = handler;
	};
	default_path = "/";
});
