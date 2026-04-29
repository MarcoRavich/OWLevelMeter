#!/bin/bash
# Auto-installer for OpenWrt Level Meter

set -e

# Configuration
ROUTER_HOST="${1:-192.168.1.1}"
ROUTER_USER="${2:-root}"
ROUTER_PORT="${3:-22}"

echo "[*] OpenWrt Level Meter Auto-Installer"
echo "[*] Target: $ROUTER_USER@$ROUTER_HOST:$ROUTER_PORT"
echo ""

# Check SSH connectivity
echo "[*] Testing SSH connection..."
if ! ssh -p $ROUTER_PORT "$ROUTER_USER@$ROUTER_HOST" "echo 'SSH OK'"; then
    echo "[ERROR] Cannot connect to router. Check IP, user, and port."
    exit 1
fi

echo "[*] Installing dependencies..."
ssh -p $ROUTER_PORT "$ROUTER_USER@$ROUTER_HOST" opkg install alsa-utils alsa-lib 2>/dev/null || true

echo "[*] Installing daemon..."
scp -P $ROUTER_PORT levelmeter-daemon.lua "$ROUTER_USER@$ROUTER_HOST:/usr/bin/"
ssh -p $ROUTER_PORT "$ROUTER_USER@$ROUTER_HOST" chmod +x /usr/bin/levelmeter-daemon

echo "[*] Installing init script..."
scp -P $ROUTER_PORT etc/init.d/levelmeter "$ROUTER_USER@$ROUTER_HOST:/etc/init.d/"
ssh -p $ROUTER_PORT "$ROUTER_USER@$ROUTER_HOST" chmod +x /etc/init.d/levelmeter

echo "[*] Installing UCI config..."
scp -P $ROUTER_PORT etc/config/levelmeter "$ROUTER_USER@$ROUTER_HOST:/etc/config/"

echo "[*] Creating LuCI directories..."
ssh -p $ROUTER_PORT "$ROUTER_USER@$ROUTER_HOST" mkdir -p /usr/share/luci-app-levelmeter/luasrc/{controller/admin,model/cbi/admin,view/admin}

echo "[*] Installing LuCI files..."
scp -P $ROUTER_PORT luci/controller/admin/levelmeter.lua "$ROUTER_USER@$ROUTER_HOST:/usr/share/luci-app-levelmeter/luasrc/controller/admin/"
scp -P $ROUTER_PORT luci/model/cbi/admin/levelmeter.lua "$ROUTER_USER@$ROUTER_HOST:/usr/share/luci-app-levelmeter/luasrc/model/cbi/admin/"
scp -P $ROUTER_PORT luci/view/admin/levelmeter_status.htm "$ROUTER_USER@$ROUTER_HOST:/usr/share/luci-app-levelmeter/luasrc/view/admin/"

echo "[*] Starting service..."
ssh -p $ROUTER_PORT "$ROUTER_USER@$ROUTER_HOST" '/etc/init.d/levelmeter enable && /etc/init.d/levelmeter start'

echo ""
echo "[✓] Installation complete!"
echo ""
echo "Access the web UI at:"
echo "  http://$ROUTER_HOST/luci/admin/services/levelmeter"
echo ""
echo "To view logs:"
echo "  ssh -p $ROUTER_PORT $ROUTER_USER@$ROUTER_HOST logread | grep levelmeter"
echo ""
echo "To test the API:"
echo "  curl -s http://$ROUTER_HOST:8765/api/meter | jq ."
