#!/bin/sh
# Menyusun livekit.yaml dari variabel lingkungan lalu menjalankan LiveKit.
#
# Wajib     : LIVEKIT_API_KEY, LIVEKIT_API_SECRET (secret ≥ 32 karakter)
# Opsional  : WEBHOOK_URL       alamat backend yang menerima event LiveKit (https://…/webhooks/livekit)
#             LOG_LEVEL         info (bawaan) | debug
# Dari Railway (otomatis ada setelah TCP Proxy dibuat):
#             RAILWAY_TCP_PROXY_DOMAIN, RAILWAY_TCP_PROXY_PORT, RAILWAY_TCP_APPLICATION_PORT
#
# Mengapa begini: Railway tidak menerima UDP, jadi suara lewat "ICE/TCP". Klien harus tersambung ke
# host:port TCP proxy yang DIPILIH Railway (port publiknya acak), maka LiveKit dibuat mendengarkan dan
# mengiklankan port publik itu, dan socat meneruskan port aplikasi proxy → port tsb di dalam kontainer.
set -eu

: "${LIVEKIT_API_KEY:?LIVEKIT_API_KEY belum diisi}"
: "${LIVEKIT_API_SECRET:?LIVEKIT_API_SECRET belum diisi}"
if [ "${#LIVEKIT_API_SECRET}" -lt 32 ]; then
  echo "LIVEKIT_API_SECRET harus minimal 32 karakter" >&2
  exit 1
fi

CONFIG=/tmp/livekit.yaml
TCP_PORT=7881
NODE_IP_LINE=""

if [ -n "${RAILWAY_TCP_PROXY_PORT:-}" ] && [ -n "${RAILWAY_TCP_PROXY_DOMAIN:-}" ]; then
  TCP_PORT="$RAILWAY_TCP_PROXY_PORT"
  APP_PORT="${RAILWAY_TCP_APPLICATION_PORT:-7882}"
  case "$RAILWAY_TCP_PROXY_DOMAIN" in
    *[!0-9.]*) NODE_IP="$(dig +short "$RAILWAY_TCP_PROXY_DOMAIN" | grep -E '^[0-9.]+$' | head -n1 || true)"
               [ -n "$NODE_IP" ] || NODE_IP="$(getent hosts "$RAILWAY_TCP_PROXY_DOMAIN" | awk '{print $1; exit}')" ;;
    *) NODE_IP="$RAILWAY_TCP_PROXY_DOMAIN" ;;  # sudah berupa IP
  esac
  if [ -z "$NODE_IP" ]; then
    echo "Tidak bisa menemukan IP untuk $RAILWAY_TCP_PROXY_DOMAIN" >&2
    exit 1
  fi
  NODE_IP_LINE="  node_ip: $NODE_IP"
  echo "ICE/TCP: klien -> $NODE_IP:$TCP_PORT (proxy Railway) -> :$APP_PORT -> LiveKit :$TCP_PORT"
  # Sambungkan lewat IP kontainer, bukan 127.0.0.1: LiveKit mengabaikan ICE dari alamat loopback.
  LOCAL_IP="$(hostname -i | awk '{print $1}')"
  socat "TCP-LISTEN:$APP_PORT,fork,reuseaddr" "TCP:$LOCAL_IP:$TCP_PORT" &
else
  echo "PERINGATAN: TCP Proxy Railway belum ada (RAILWAY_TCP_PROXY_* kosong). Signalling jalan, tetapi suara TIDAK akan tersambung." >&2
  echo "Buat TCP Proxy (application port 7882) di Settings > Networking lalu redeploy." >&2
fi

{
  echo "port: 7880"
  echo "log_level: ${LOG_LEVEL:-info}"
  echo "rtc:"
  echo "  tcp_port: $TCP_PORT"
  echo "  use_external_ip: false"
  echo "  skip_external_ip_validation: true"
  [ -n "$NODE_IP_LINE" ] && echo "$NODE_IP_LINE"
  echo "  port_range_start: 50000"
  echo "  port_range_end: 50100"
  echo "keys:"
  echo "  $LIVEKIT_API_KEY: $LIVEKIT_API_SECRET"
  if [ -n "${WEBHOOK_URL:-}" ]; then
    echo "webhook:"
    echo "  api_key: $LIVEKIT_API_KEY"
    echo "  urls:"
    echo "    - $WEBHOOK_URL"
  fi
} > "$CONFIG"

exec /livekit-server --config "$CONFIG"
