-- Copyright (C) 2009 Florian Zeitz
-- Copyright (C) 2009 Matthew Wild
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--
local st = require "util.stanza";

local chef = {  
  { th = "t" }, 

  { ow = "o"},
  {["([^%w])o"] = "%1oo",
  O = "Oo"},

  {au = "oo",
  u = "oo", U = "Oo"},
  {["([^o])o([^o])"] = "%1u%2"},
  {ir = "ur",

  an = "un", An = "Un", Au = "Oo"},

  {e = "i", E = "I"},

  { i = function () return select(math.random(2), "i", "ee"); end },

  {a = "e", A = "E"},

  {["e([^%w])"] = "e-a%1"},
  {f = "ff"}, 

  {v = "f", V = "F"},
  {w = "v", W = "V"} };
  
function swedish(english)
	local eng, url = english:match("(.*)(http://.*)$");
	if eng then english = eng; end

	for _,v in ipairs(chef) do
		for k,v in pairs(v) do
			english = english:gsub(k,v);
		end
	end
	english = english:gsub("the", "zee");
	english = english:gsub("The", "Zee");
	english = english:gsub("tion", "shun");
	english = english:gsub("[.!?]$", "%1\nBork Bork Bork!");
	return tostring(english..((url and url) or ""));
end

function check_message(data)
	local origin, stanza = data.origin, data.stanza;
	
	local body, bodyindex;
	for k,v in ipairs(stanza) do
		if v.name == "body" then
			body, bodyindex = v, k;
		end
	end
	
	if not body then return; end
	body = body:get_text();
	
	if body then
		stanza[bodyindex][1] = swedish(body);
	end
end

module:hook("message/bare", check_message);

