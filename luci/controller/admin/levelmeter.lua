module("luci.controller.admin.levelmeter", package.seeall)

function index()
    entry({"admin", "services", "levelmeter"}, cbi("admin/levelmeter"), "Audio Level Meter", 95)
    entry({"admin", "services", "levelmeter", "api", "status"}, call("api_status"))
    entry({"admin", "services", "levelmeter", "api", "meter"}, call("api_meter"))
end

function api_status()
    local rv = {}
    local pid = io.open("/var/run/levelmeter.pid", "r")
    
    if pid then
        rv.running = true
        pid:close()
    else
        rv.running = false
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(rv)
end

function api_meter()
    -- Proxy request to daemon HTTP API
    local socket = require "socket"
    local http = require "socket.http"
    local json = require "cjson"
    
    local response_body = {}
    local handler = function(chunk)
        if chunk ~= "" then
            table.insert(response_body, chunk)
        end
    end
    
    local _, status, headers, _ = http.request({
        url = "http://127.0.0.1:8765/api/meter",
        sink = handler,
        timeout = 2
    })
    
    local body = table.concat(response_body)
    
    if status == 200 then
        luci.http.prepare_content("application/json")
        luci.http.write(body)
    else
        luci.http.prepare_content("application/json")
        luci.http.write_json({ error = "Daemon not responding", status = status })
    end
end
