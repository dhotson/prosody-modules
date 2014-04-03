-- Provides total CPU time, useful for DERIVE

module:provides("statistics", {
	statistics = {
		cpu_total = { -- milliseconds of CPU time used
			get = function()
				return os.clock() * 1000;
			end
		}
	}
});
