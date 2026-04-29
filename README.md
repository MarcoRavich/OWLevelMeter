# OpenWrt Level Meter (OWLevelMeter)

A real-time audio level meter for OpenWrt/LuCI that monitors ALSA device input channels and displays VU meters in the LuCI web interface.

## Features

- ✅ **Real-time VU Meters** — Stereo L/R channels (easily extensible to multi-channel)
- ✅ **Visual Bars** — Green→Orange→Red gradient based on signal level
- ✅ **Peak Hold** — Holds peak level for 2.5 seconds with smooth decay
- ✅ **Clipping Detection** — Red flash alert when signal clips (≥0.9999)
- ✅ **dB Display** — Numeric display ranging -60 to 0 dB
- ✅ **Device Selection** — Choose any ALSA input device
- ✅ **Lightweight** — Pure Lua backend + HTML5 frontend, zero external dependencies
- ✅ **Low Resource** — Minimal CPU footprint on embedded devices

## Architecture

### Backend
- **Daemon** (`levelmeter-daemon.lua`) — Lua daemon using ALSA capture
  - Reads audio frames from ALSA device
  - Calculates RMS, peak, clipping detection
  - Exposes HTTP JSON API on `127.0.0.1:8765`
  - Auto-restarts via procd service manager

### Frontend
- **LuCI Web UI** — Real-time dashboard
  - RESTful polling (100ms default)
  - Canvas-based VU meter visualization
  - Device management
  - Configuration panel

### Init Script
- **procd Service** — Managed service lifecycle

## Installation

### Quick Install (Auto-Script)

```bash
# On your OpenWrt router
ssh root@192.168.1.1 'bash -s' < <(curl -fsSL https://raw.githubusercontent.com/MarcoRavich/OWLevelMeter/main/install.sh)
```

### Manual Installation

1. **Install dependencies:**
   ```bash
   opkg install alsa-utils alsa-lib
   ```

2. **Copy files to router:**
   ```bash
   git clone https://github.com/MarcoRavich/OWLevelMeter.git
   cd OWLevelMeter
   
   scp levelmeter-daemon.lua root@192.168.1.1:/usr/bin/
   ssh root@192.168.1.1 chmod +x /usr/bin/levelmeter-daemon
   
   scp etc/init.d/levelmeter root@192.168.1.1:/etc/init.d/
   ssh root@192.168.1.1 chmod +x /etc/init.d/levelmeter
   
   scp etc/config/levelmeter root@192.168.1.1:/etc/config/
   
   ssh root@192.168.1.1 mkdir -p /usr/share/luci-app-levelmeter/luasrc/{controller/admin,model/cbi/admin,view/admin}
   
   scp luci/controller/admin/levelmeter.lua root@192.168.1.1:/usr/share/luci-app-levelmeter/luasrc/controller/admin/
   scp luci/model/cbi/admin/levelmeter.lua root@192.168.1.1:/usr/share/luci-app-levelmeter/luasrc/model/cbi/admin/
   scp luci/view/admin/levelmeter_status.htm root@192.168.1.1:/usr/share/luci-app-levelmeter/luasrc/view/admin/
   
   ssh root@192.168.1.1 '/etc/init.d/levelmeter enable && /etc/init.d/levelmeter start'
   ```

3. **Access the UI:**
   ```
   http://192.168.1.1/luci/admin/services/levelmeter
   ```

## Configuration

### Via LuCI Web Interface
Navigate to **System → Audio Level Meter** to:
- Select audio input device
- Configure sample rate
- Adjust frame size
- Enable/disable service

### Via UCI Command Line

```bash
# Set device (hw:0,0 = Card 0, Device 0)
uci set levelmeter.general.device="0"
uci set levelmeter.general.card="0"

# Enable service
uci set levelmeter.general.enabled="1"

# Save and restart
uci commit levelmeter
/etc/init.d/levelmeter restart
```

### UCI Config File (`/etc/config/levelmeter`)

```
config general
    option enabled '1'
    option device 'hw:0,0'
    option card '0'
    option channels '2'
    option sample_rate '48000'
    option frame_size '1024'
    option http_port '8765'
```

## API Endpoints

### GET `/api/meter`
Returns current audio metrics in JSON format.

**Response:**
```json
{
  "status": "ok",
  "device": "hw:0,0",
  "channels": 2,
  "dbL": -15.3,
  "dbR": -16.8,
  "peakL": -8.2,
  "peakR": -7.1,
  "clipping": false,
  "timestamp": 1704067200.123
}
```

### GET `/health`
Health check endpoint.

**Response:**
```json
{
  "status": "running"
}
```

## Finding Your Audio Device

```bash
# List all ALSA devices
ssh root@192.168.1.1 'arecord -l'

# Example output:
# **** List of CAPTURE Hardware Devices ****
# card 0: PCH [HDA Intel PCH], device 0: ALC269 Analog [ALC269 Analog]
#   Subdevices: 1/1
#   Subdevice #0: subdevice #0

# Use format: hw:CARD,DEVICE
# For example: hw:0,0
```

## Troubleshooting

### Daemon not starting

```bash
# Check service status
ssh root@192.168.1.1 '/etc/init.d/levelmeter status'

# View logs
ssh root@192.168.1.1 'logread | grep levelmeter'

# Start manually with debug
ssh root@192.168.1.1 '/usr/bin/levelmeter-daemon config 0 2 48000'
```

### No audio levels showing

1. Verify ALSA device exists:
   ```bash
   ssh root@192.168.1.1 'arecord -l'
   ```

2. Test direct audio capture:
   ```bash
   ssh root@192.168.1.1 'arecord -D hw:0,0 -f S16_LE -c 2 -r 48000 -t wav /tmp/test.wav &'
   sleep 5
   ssh root@192.168.1.1 'kill %1'
   ```

3. Check HTTP API directly:
   ```bash
   curl -s http://192.168.1.1:8765/api/meter | jq .
   ```

### Device selection not working

Clear old configuration:
```bash
ssh root@192.168.1.1 'rm /etc/config/levelmeter && /etc/init.d/levelmeter restart'
```

## Extending to Multi-Channel

To support more than 2 channels:

1. Edit `/etc/config/levelmeter`:
   ```
   option channels '6'
   ```

2. Modify `levelmeter-daemon.lua`:
   - Update channel parsing in `read_and_analyze_frame()`
   - Add peak tracking for each channel

3. Update `luci/view/admin/levelmeter_status.htm`:
   - Add more VU meter bars in JavaScript `renderMeters()`

## Performance

- **CPU Usage:** ~2-5% on typical OpenWrt router (MT7621)
- **Memory:** ~5-10 MB (daemon + LuCI process)
- **Update Rate:** 100ms default (configurable)
- **Latency:** ~200-300ms (arecord buffering + HTTP polling)

## License

Based on [LevelMeter](https://github.com/mrmazure/LevelMeter) by MrMazure

## Contributing

Pull requests welcome! Areas for improvement:
- Multi-channel support
- Spectrum analyzer
- LUFS metering
- WebSocket streaming (lower latency)
- Mobile app

## Support

For issues and feature requests, open an issue on [GitHub](https://github.com/MarcoRavich/OWLevelMeter/issues).
