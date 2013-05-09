local usermanager = require "core.usermanager"
local httpserver = require "net.httpserver"
local jidutil = require "util.jid"
local hmac = require "hmac"

local base64 = require "util.encodings".base64

local humane = require "util.serialization".serialize

-- Configuration
local base = "openid"
local openidns = "http://specs.openid.net/auth/2.0" -- [#4.1.2]
local response_404 = { status = "404 Not Found", body = "<h1>Page Not Found</h1>Sorry, we couldn't find what you were looking for :(" };

local associations = {}

local function genkey(length)
    -- FIXME not cryptographically secure
    str = {}
    
    for i = 1,length do
        local rand = math.random(33, 126)
        table.insert(str, string.char(rand))
    end

    return table.concat(str)
end

local function tokvstring(dict)
    -- key-value encoding for a dictionary [#4.1.3]
    local str = ""
    
    for k,v in pairs(dict) do
        str = str..k..":"..v.."\n"
    end

    return str
end

local function newassoc(key, shared)
    -- TODO don't use genkey here
    local handle = genkey(16)
    associations[handle] = {}
    associations[handle]["key"] = key
    associations[handle]["shared"] = shared
    associations[handle]["time"] = os.time()
    return handle
end

local function split(str, sep)
    local splits = {}
    str:gsub("([^.."..sep.."]*)"..sep, function(c) table.insert(splits, c) end)
    return splits
end

local function sign(response, key)
    local fields = {}

    for _,field in pairs(split(response["openid.signed"],",")) do
       fields[field] = response["openid."..field]
    end

    -- [#10.1]
    return base64.encode(hmac.sha256(key, tokvstring(fields)))
end

local function urlencode(s)
    return (string.gsub(s, "%W",
        function(str)
            return string.format("%%%02X", string.byte(str))
        end))
end

local function urldecode(s)
    return(string.gsub(string.gsub(s, "+", " "), "%%(%x%x)",
        function(str)
            return string.char(tonumber(str,16))
        end))
end

local function utctime()
    local now = os.time()
    local diff = os.difftime(now, os.time(os.date("!*t", now)))
    return now-diff
end

local function nonce()
    -- generate a response nonce [#10.1]
    local random = ""
    for i=0,10 do
        random = random..string.char(math.random(33,126))
    end
    
    local timestamp = os.date("%Y-%m-%dT%H:%M:%SZ", utctime())

    return timestamp..random
end

local function query_params(query)
    if type(query) == "string" and #query > 0 then
        if query:match("=") then
            local params = {}
            for k, v in query:gmatch("&?([^=%?]+)=([^&%?]+)&?") do
                if k and v then
                    params[urldecode(k)] = urldecode(v)
                end
            end
            return params
        else
            return urldecode(query)
        end
    end
end

local function split_host_port(combined)
    local host = combined
    local port = ""
    local cpos = string.find(combined, ":")
    if cpos ~= nil then
        host = string.sub(combined, 0, cpos-1)
        port = string.sub(combined, cpos+1)
    end

    return host, port
end

local function toquerystring(dict)
    -- query string encoding for a dictionary [#4.1.3]
    local str = ""

    for k,v in pairs(dict) do
        str = str..urlencode(k).."="..urlencode(v).."&"
    end

    return string.sub(str, 0, -1)
end

local function match_realm(url, realm)
    -- FIXME do actual match [#9.2]
    return true
end

local function handle_endpoint(method, body, request)
    module:log("debug", "Request at OpenID provider endpoint")
    
    local params = nil

    if method == "GET" then
        params = query_params(request.url.query)
    elseif method == "POST" then
        params = query_params(body)
    else
        -- TODO error
        return response_404
    end
    
    module:log("debug", "Request Parameters:\n"..humane(params))

    if params["openid.ns"] == openidns then
        -- OpenID 2.0 request [#5.1.1]
        if params["openid.mode"] == "associate" then
            -- Associate mode [#8]
            -- TODO implement association

            -- Error response [#8.2.4]
            local openidresponse = {
               ["ns"] = openidns,
               ["session_type"] = params["openid.session_type"],
               ["assoc_type"] = params["openid.assoc_type"],
               ["error"] = "Association not supported... yet",
               ["error_code"] = "unsupported-type",
            }

            local kvresponse = tokvstring(openidresponse)
            module:log("debug", "OpenID Response:\n"..kvresponse)
            return {
                headers = {
                    ["Content-Type"] = "text/plain"
                },
                body = kvresponse
            }
        elseif params["openid.mode"] == "checkid_setup" or params["openid.mode"] == "checkid_immediate" then
            -- Requesting authentication [#9]
            if not params["openid.realm"] then
                -- set realm to default value of return_to [#9.1]
                if params["openid.return_to"] then
                    params["openid.realm"] = params["openid.return_to"]
                else
                    -- neither was sent, error [#9.1]
                    -- FIXME return proper error
                    return response_404
                end
            end

            if params["openid.return_to"] then
                -- Assure that the return_to url matches the realm [#9.2]
                if not match_realm(params["openid.return_to"], params["openid.realm"]) then
                    -- FIXME return proper error
                    return response_404
                end

                -- Verify the return url [#9.2.1]
                -- TODO implement return url verification
            end
            
            if params["openid.claimed_id"] and params["openid.identity"] then
                -- asserting an identifier [#9.1]

                if params["openid.identity"] == "http://specs.openid.net/auth/2.0/identifier_select" then
                    -- automatically select an identity [#9.1]
                    params["openid.identity"] = params["openid.claimed_id"]
                end

                if params["openid.mode"] == "checkid_setup" then
                    -- Check ID Setup mode
                    -- TODO implement: NEXT STEP
                    local head = "<title>Prosody OpenID : Login</title>"
                    local body = string.format([[
<p>Open ID Authentication<p>
<p>Identifier: <tt>%s</tt></p>
<p>Realm: <tt>%s</tt></p>
<p>Return: <tt>%s</tt></p>
<form method="POST" action="%s">
    Jabber ID: <input type="text" name="jid"/><br/>
    Password: <input type="password" name="password"/><br/>
    <input type="hidden" name="openid.return_to" value="%s"/>
    <input type="submit" value="Authenticate"/>
</form>
                    ]], params["openid.claimed_id"], params["openid.realm"], params["openid.return_to"], base, params["openid.return_to"])

                    return string.format([[
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />
%s
</head>
<body>
%s
</body>
</html>
                    ]], head, body)
                elseif params["openid.mode"] == "checkid_immediate" then
                    -- Check ID Immediate mode [#9.3]
                    -- TODO implement check id immediate
                end
            else
                -- not asserting an identifier [#9.1]
                -- used for extensions
                -- TODO implement common extensions
            end
        elseif params["openid.mode"] == "check_authentication" then
            module:log("debug", "OpenID Check Authentication Mode")
            local assoc = associations[params["openid.assoc_handle"]]
            module:log("debug", "Checking Association Handle: "..params["openid.assoc_handle"])
            if assoc and not assoc["shared"] then
                module:log("debug", "Found valid association")
                local sig = sign(params, assoc["key"])

                local is_valid = "false"
                if sig == params["openid.sig"] then
                    is_valid = "true"
                end

                module:log("debug", "Signature is: "..is_valid)
                
                openidresponse = {
                    ns = openidns,
                    is_valid = is_valid, 
                }

                -- Delete this association
                associations[params["openid.assoc_handle"]] = nil
                return {
                    headers = {
                        ["Content-Type"] = "text/plain"
                    },
                    body = tokvstring(openidresponse),
                }
            else
                module:log("debug", "No valid association")
                -- TODO return error
                -- Invalidate the handle [#11.4.2.2]
            end
        else
            -- Some other mode
            -- TODO error
        end
    elseif params["password"] then
        -- User is authenticating
        local user, domain = jidutil.split(params["jid"])
        module:log("debug", "Authenticating "..params["jid"].." ("..user..","..domain..") with password: "..params["password"])
        local valid = usermanager.validate_credentials(domain, user, params["password"], "PLAIN")
        if valid then
            module:log("debug", "Authentication Succeeded: "..params["jid"])
            if params["openid.return_to"] ~= "" then
                -- TODO redirect the user to return_to with the openid response
                -- included, need to handle the case if its a GET, that there are
                -- existing query parameters on the return_to URL [#10.1]
                local host, port = split_host_port(request.headers.host)
                local endpointurl = ""
                if port == '' then
                    endpointurl = string.format("http://%s/%s", host, base)
                else
                    endpointurl = string.format("http://%s:%s/%s", host, port, base)
                end
                
                local nonce = nonce()
                local key = genkey(32)
                local assoc_handle = newassoc(key)

                local openidresponse = {
                    ["openid.ns"] = openidns,
                    ["openid.mode"] = "id_res",
                    ["openid.op_endpoint"] = endpointurl,
                    ["openid.claimed_id"] = endpointurl.."/"..user,
                    ["openid.identity"] = endpointurl.."/"..user,
                    ["openid.return_to"] = params["openid.return_to"],
                    ["openid.response_nonce"] = nonce,
                    ["openid.assoc_handle"] = assoc_handle,
                    ["openid.signed"] = "op_endpoint,identity,claimed_id,return_to,assoc_handle,response_nonce", -- FIXME
                    ["openid.sig"] = nil,
                }

                openidresponse["openid.sig"] = sign(openidresponse, key)

                queryresponse = toquerystring(openidresponse)

                redirecturl = params["openid.return_to"]
                -- add the parameters to the return_to
                if redirecturl:match("?") then
                    redirecturl = redirecturl.."&"
                else
                    redirecturl = redirecturl.."?"
                end

                redirecturl = redirecturl..queryresponse

                module:log("debug", "Open ID Positive Assertion Response Table:\n"..humane(openidresponse))
                module:log("debug", "Open ID Positive Assertion Response URL:\n"..queryresponse)
                module:log("debug", "Redirecting User to:\n"..redirecturl)
                return {
                    status = "303 See Other",
                    headers = {
                        Location = redirecturl,
                    },
                    body = "Redirecting to: "..redirecturl -- TODO Include a note with a hyperlink to redirect
                }
            else
                -- TODO Do something useful is there is no return_to
            end
        else
            module:log("debug", "Authentication Failed: "..params["jid"])
            -- TODO let them try again
        end
    else
        -- Not an Open ID request, do something useful
        -- TODO
    end

    return response_404
end

local function handle_identifier(method, body, request, id)
    module:log("debug", "Request at OpenID identifier")
    local host, port = split_host_port(request.headers.host)

    local user_name = ""
    local user_domain = ""
    local apos = string.find(id, "@")
    if apos == nil then
        user_name = id
        user_domain = host
    else
        user_name = string.sub(id, 0, apos-1)
        user_domain = string.sub(id, apos+1)
    end

    user, domain = jidutil.split(id)

    local exists = usermanager.user_exists(user_name, user_domain)
    
    if not exists then
        return response_404 
    end
    
    local endpointurl = ""
    if port == '' then
        endpointurl = string.format("http://%s/%s", host, base)
    else
        endpointurl = string.format("http://%s:%s/%s", host, port, base)
    end

    local head = string.format("<title>Prosody OpenID : %s@%s</title>", user_name, user_domain)
    -- OpenID HTML discovery [#7.3]
    head = head .. string.format('<link rel="openid2.provider" href="%s" />', endpointurl)
    
    local content = 'request.url.path: ' .. request.url.path .. '<br/>'
    content = content .. 'host+port: ' .. request.headers.host .. '<br/>'
    content = content .. 'host: ' .. tostring(host) .. '<br/>'
    content = content .. 'port: ' .. tostring(port) .. '<br/>'
    content = content .. 'user_name: ' .. user_name .. '<br/>'
    content = content .. 'user_domain: ' .. user_domain .. '<br/>'
    content = content .. 'exists: ' .. tostring(exists) .. '<br/>'
    
    local body = string.format('<p>%s</p>', content)
	
    local data = string.format([[
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />
%s
</head>
<body>
%s
</body>
</html>
    ]], head, body)
    return data;
end

local function handle_request(method, body, request)
    module:log("debug", "Received request")

    -- Make sure the host is enabled
    local host = split_host_port(request.headers.host)
    if not hosts[host] then
        return response_404
    end

    if request.url.path == "/"..base then
        -- OpenID Provider Endpoint
        return handle_endpoint(method, body, request)
    else
        local id = request.url.path:match("^/"..base.."/(.+)$")
        if id then
            -- OpenID Identifier
            return handle_identifier(method, body, request, id)
        else
            return response_404
        end
    end
end

httpserver.new{ port = 5280, base = base, handler = handle_request, ssl = false}
