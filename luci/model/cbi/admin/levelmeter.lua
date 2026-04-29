m = Map("levelmeter", translate("Audio Level Meter"), translate("Real-time ALSA audio level monitoring"))

s = m:section(TypedSection, "general", translate("Settings"))
s.anonymous = true

enabled = s:option(Flag, "enabled", translate("Enable Service"))
enabled.default = 0
enabled.description = translate("Start the Level Meter daemon on boot")

device = s:option(Value, "device", translate("Audio Device"))
device.description = translate("ALSA device ID (e.g., hw:0,0)")
device.default = "hw:0,0"

card = s:option(Value, "card", translate("Card Number"))
card.description = translate("Sound card index (0, 1, etc.)")
card.datatype = "uinteger"
card.default = 0

channels = s:option(Value, "channels", translate("Channels"))
channels.description = translate("Number of audio channels (usually 2 for stereo)")
channels.datatype = "uinteger"
channels.default = 2

sample_rate = s:option(Value, "sample_rate", translate("Sample Rate"))
sample_rate.description = translate("Audio sample rate in Hz (e.g., 48000)")
sample_rate.datatype = "uinteger"
sample_rate.default = 48000

frame_size = s:option(Value, "frame_size", translate("Frame Size"))
frame_size.description = translate("Number of samples per frame (1024 is typical)")
frame_size.datatype = "uinteger"
frame_size.default = 1024

http_port = s:option(Value, "http_port", translate("HTTP Port"))
http_port.description = translate("Port for API server (default: 8765)")
http_port.datatype = "uinteger"
http_port.default = 8765

return m
