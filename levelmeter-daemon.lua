#!/usr/bin/lua
--[[
  Level Meter Daemon for OpenWrt
  Real-time audio metering via ALSA
  Exposes HTTP JSON API on 127.0.0.1:8765
]]

local socket = require("socket")
local json = require("cjson")

-- Configuration
local CONFIG = {
    device = os.getenv("LM_DEVICE") or "hw:0,0",
    channels = 2,
    sample_rate = 48000,
    frame_size = 1024,
    http_port = 8765,
    http_host = "127.0.0.1",
}

-- Global state
local state = {
    running = false,
    peakL = -math.huge,
    peakR = -math.huge,
    peakLTime = 0,
    peakRTime = 0,
    PEAK_HOLD_MS = 2500,
    clipTimer = 0,
    CLIP_HOLD_MS = 1200,
    lastClip = false,
    dbL = -60,
    dbR = -60,
}

local http_socket = nil
local fifo_handle = nil
local last_update = 0

-- ═══════════════════════════════════════════════
-- DSP UTILITIES (ported from LevelMeter app.js)
-- ═══════════════════════════════════════════════

--- Convert linear value (0-1) to dBFS
local function linToDb(lin)
    if lin > 0 then
        return 20 * math.log10(lin)
    else
        return -math.huge
    end
end

--- Calculate RMS from raw audio samples
local function calculateRMS(data, start_pos, count)
    if count <= 0 then return 0 end
    local sum = 0
    for i = start_pos, start_pos + count - 1 do
        if data[i] then
            sum = sum + (data[i] * data[i])
        end
    end
    return math.sqrt(sum / count)
end

--- Find peak from raw audio samples
local function calculatePeak(data, start_pos, count)
    if count <= 0 then return 0 end
    local max = 0
    for i = start_pos, start_pos + count - 1 do
        if data[i] then
            local v = math.abs(data[i])
            if v > max then max = v end
        end
    end
    return max
end

--- Detect clipping (signal >= 0.9999)
local function isClipping(peak)
    return peak >= 0.9999
end

-- ═══════════════════════════════════════════════
-- AUDIO CAPTURE VIA ARECORD + FIFO
-- ═══════════════════════════════════════════════

local function start_audio_capture()
    -- Create named pipe
    os.execute("mkfifo /tmp/levelmeter_fifo 2>/dev/null")
    
    -- Start arecord in background, writing to FIFO
    -- Format: -f S16_LE (signed 16-bit), -c 2 (stereo), -r 48000 (sample rate), -t raw (raw format)
    local cmd = string.format(
        "arecord -D '%s' -f S16_LE -c %d -r %d -t raw /tmp/levelmeter_fifo 2>/dev/null &",
        CONFIG.device,
        CONFIG.channels,
        CONFIG.sample_rate
    )
    os.execute(cmd)
    
    -- Open FIFO for reading
    fifo_handle = io.open("/tmp/levelmeter_fifo", "rb")
    if not fifo_handle then
        print("[ERROR] Failed to open FIFO")
        return false
    end
    return true
end

local function stop_audio_capture()
    if fifo_handle then
        fifo_handle:close()
        fifo_handle = nil
    end
    os.execute("killall arecord 2>/dev/null")
    os.execute("rm -f /tmp/levelmeter_fifo 2>/dev/null")
end

-- ═══════════════════════════════════════════════
-- AUDIO FRAME READING & ANALYSIS
-- ═══════════════════════════════════════════════

local function read_and_analyze_frame()
    if not fifo_handle then return false end
    
    -- Read raw audio bytes (frame_size samples * 2 channels * 2 bytes per sample)
    local bytes_needed = CONFIG.frame_size * CONFIG.channels * 2
    local data = fifo_handle:read(bytes_needed)
    
    if not data or #data < bytes_needed then
        return false
    end
    
    -- Parse 16-bit signed samples (little-endian)
    local samples = {}
    for i = 1, #data, 2 do
        local byte1 = string.byte(data, i)
        local byte2 = string.byte(data, i + 1)
        local sample = byte1 + (byte2 * 256)
        if sample >= 32768 then sample = sample - 65536 end
        table.insert(samples, sample / 32768.0)  -- Normalize to [-1, 1]
    end
    
    if #samples < CONFIG.frame_size * CONFIG.channels then
        return false
    end
    
    -- De-interleave channels
    local ch_L = {}
    local ch_R = {}
    for i = 1, CONFIG.frame_size do
        table.insert(ch_L, samples[i * 2 - 1] or 0)
        table.insert(ch_R, samples[i * 2] or 0)
    end
    
    -- Calculate metrics
    local rms_L = calculateRMS(ch_L, 1, #ch_L)
    local rms_R = calculateRMS(ch_R, 1, #ch_R)
    local peak_L = calculatePeak(ch_L, 1, #ch_L)
    local peak_R = calculatePeak(ch_R, 1, #ch_R)
    
    local db_L = linToDb(rms_L)
    local db_R = linToDb(rms_R)
    local clipping = isClipping(peak_L) or isClipping(peak_R)
    
    local now = socket.gettime() * 1000  -- ms
    
    -- Update peaks with hold
    if db_L > state.peakL then
        state.peakL = db_L
        state.peakLTime = now
    elseif now - state.peakLTime > state.PEAK_HOLD_MS then
        state.peakL = math.max(state.peakL - 0.5, -60)
    end
    
    if db_R > state.peakR then
        state.peakR = db_R
        state.peakRTime = now
    elseif now - state.peakRTime > state.PEAK_HOLD_MS then
        state.peakR = math.max(state.peakR - 0.5, -60)
    end
    
    -- Update clipping hold
    if clipping then
        state.clipTimer = now
        state.lastClip = true
    elseif now - state.clipTimer > state.CLIP_HOLD_MS then
        state.lastClip = false
    end
    
    -- Store current levels
    state.dbL = db_L
    state.dbR = db_R
    state.peakDbL = linToDb(peak_L)
    state.peakDbR = linToDb(peak_R)
    state.isClipping = clipping
    
    return true
end

-- ═══════════════════════════════════════════════
-- HTTP API SERVER
-- ═══════════════════════════════════════════════

local function init_http_server()
    http_socket = socket.tcp()
    http_socket:setoption("reuseaddr", true)
    local ok, err = http_socket:bind(CONFIG.http_host, CONFIG.http_port)
    if not ok then
        print("[ERROR] Failed to bind HTTP socket: " .. err)
        return false
    end
    http_socket:listen(5)
    http_socket:settimeout(0.1)  -- Non-blocking
    return true
end

local function handle_http_client(client)
    client:settimeout(1)
    local request = client:receive("*a")
    if not request then
        client:close()
        return
    end
    
    -- Simple GET request parsing
    local path = request:match("GET ([^ ]*)")
    local response_body
    local status_code = "200 OK"
    
    if path == "/api/meter" then
        response_body = json.encode({
            status = "ok",
            device = CONFIG.device,
            channels = 2,
            dbL = math.floor(state.dbL * 10) / 10,
            dbR = math.floor(state.dbR * 10) / 10,
            peakL = math.floor(state.peakL * 10) / 10,
            peakR = math.floor(state.peakR * 10) / 10,
            clipping = state.lastClip,
            timestamp = socket.gettime()
        })
    elseif path == "/health" then
        response_body = json.encode({ status = "running" })
    else
        status_code = "404 Not Found"
        response_body = json.encode({ error = "Not found" })
    end
    
    local response = "HTTP/1.1 " .. status_code .. "\r\n"
    response = response .. "Content-Type: application/json\r\n"
    response = response .. "Content-Length: " .. #response_body .. "\r\n"
    response = response .. "Access-Control-Allow-Origin: *\r\n"
    response = response .. "Connection: close\r\n\r\n"
    response = response .. response_body
    
    client:send(response)
    client:close()
end

local function http_poll()
    if not http_socket then return end
    local client, err = http_socket:accept()
    if client then
        handle_http_client(client)
    end
end

-- ═══════════════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════════════

local function main_loop()
    print("[INFO] Level Meter Daemon starting...")
    print("[INFO] Device: " .. CONFIG.device)
    print("[INFO] HTTP Server: http://" .. CONFIG.http_host .. ":" .. CONFIG.http_port)
    
    if not init_http_server() then
        return false
    end
    
    if not start_audio_capture() then
        return false
    end
    
    state.running = true
    print("[INFO] Daemon running. Press Ctrl+C to stop.")
    
    while state.running do
        -- Analyze audio frame
        read_and_analyze_frame()
        
        -- Handle HTTP requests
        http_poll()
        
        -- Small sleep to prevent CPU spinning
        socket.sleep(0.01)
    end
    
    stop_audio_capture()
    if http_socket then
        http_socket:close()
    end
    
    print("[INFO] Daemon stopped.")
    return true
end

-- ═══════════════════════════════════════════════
-- SIGNAL HANDLING
-- ═══════════════════════════════════════════════

local function setup_signal_handlers()
    -- Graceful shutdown on SIGTERM/SIGINT
    os.execute("trap 'exit' SIGTERM SIGINT")
end

-- ═══════════════════════════════════════════════
-- ENTRY POINT
-- ═══════════════════════════════════════════════

if arg[1] == "config" then
    -- Load config from UCI
    CONFIG.device = arg[2] or CONFIG.device
    CONFIG.channels = tonumber(arg[3]) or CONFIG.channels
    CONFIG.sample_rate = tonumber(arg[4]) or CONFIG.sample_rate
end

setup_signal_handlers()
main_loop()
