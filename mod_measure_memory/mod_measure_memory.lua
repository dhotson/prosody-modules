module:set_global();

local measure = require"core.statsmanager".measure;
local have_pposix, pposix = pcall(require, "util.pposix");

local measures = {};
setmetatable(measures, {
	__index = function (t, k, m)
		m = measure("sizes", "memory."..k); t[k] = m; return m;
	end
});

module:hook("stats-update", function ()
	measures.lua(collectgarbage("count")*1024);
end);

if have_pposix and pposix.meminfo then
	module:hook_global("stats-update", function ()
		local m = measures;
		for k, v in pairs(pposix.meminfo()) do
			m[k](v);
		end
	end);
end

local statm = io.open("/proc/self/statm");
if statm then
	statm:close();
	local pagesize = module:get_option_number("memory_pagesize", 4096); -- getconf PAGESIZE

	module:hook("stats-update", function ()
		local statm, err = io.open("/proc/self/statm");
		if not statm then
			module:log("error", tostring(err));
			return;
		end
		-- virtual memory (caches, opened librarys, everything)
		measures.total(statm:read("*n") * pagesize);
		-- resident set size (actually used memory)
		measures.rss(statm:read("*n") * pagesize);
		statm:close();
	end);
end
