# LiveKit server for Railway (uji coba). Semua pengaturan ada di repo ini + variabel Railway; lihat README.md.
FROM livekit/livekit-server:v1.13.7

# socat: meneruskan port TCP proxy Railway ke port ICE/TCP LiveKit. bind-tools: `dig`, untuk mencari IP publik proxy.
RUN apk add --no-cache socat bind-tools

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 7880
ENTRYPOINT ["/entrypoint.sh"]
