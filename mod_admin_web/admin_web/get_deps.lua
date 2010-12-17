#!/usr/bin/env lua

files = {
	["www_files/strophejs.tar.gz"] = "http://download.github.com/metajack-strophejs-release-1.0-0-g1581b37.tar.gz";
	["www_files/js/jquery-1.4.4.min.js"] = "http://code.jquery.com/jquery-1.4.4.min.js";
}

function fetch(url)
	local http = require "socket.http";
	local body, status = http.request(url);
	if status == 200 then
		return body;
	end
	return false, "HTTP status code: "..tostring(status);
end

for filename, url in pairs(files) do
	file = io.open(filename, "w+");
	data, error = fetch(url);
	if data then
		file:write(data);
	else
		print("Error: " .. error);
	end
	file:close();
end

os.execute("cd www_files && tar xzf strophejs.tar.gz");
os.execute("cd www_files/metajack-strophejs-3ada7f5 && make strophe.js && cp strophe.js ../js/strophe.js");
os.execute("rm -r www_files/strophejs.tar.gz www_files/metajack-strophejs-3ada7f5");
