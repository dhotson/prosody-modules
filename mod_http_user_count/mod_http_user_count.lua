local it = require "util.iterators";

module:depends("http");

module:provides("http", {
    route = {
        ["GET /sessions"] = function () return tostring(it.count(it.keys(prosody.full_sessions))); end;
        ["GET /users"] = function () return tostring(it.count(it.keys(prosody.bare_sessions))); end;
    };
});
