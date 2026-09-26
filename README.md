# LiveKit di Railway (uji coba Kampung Bahasa Pare)

Server LiveKit untuk panggilan suara Pare, dideploy dari repo GitHub ini. **Semua pengaturan ada di repo**
(`Dockerfile`, `entrypoint.sh`, `railway.json`); di Railway hanya perlu mengisi beberapa variabel.

> Untuk **uji coba**. Railway tidak menerima UDP, jadi suara lewat TCP (sedikit lebih tersendat dan lebih boros dibanding UDP).
> Produksi sebaiknya VM dengan UDP terbuka.

## Yang ada di repo

| Berkas | Fungsi |
| --- | --- |
| `Dockerfile` | LiveKit server v1.13.7 + `socat` |
| `entrypoint.sh` | menyusun konfigurasi dari variabel, mengatur port ICE/TCP, menjalankan LiveKit |
| `railway.json` | build dari Dockerfile, health check `/` |

## Deploy (sekali)

1. **Buat repo GitHub** dari isi folder ini (folder ini sendiri boleh jadi repo, mis. `titian-livekit`; atau taruh di monorepo dan isi
   *Root Directory* = `livekit-railway` di Railway):
   ```bash
   cd livekit-railway
   git init && git add . && git commit -m "LiveKit untuk Railway"
   git branch -M main
   git remote add origin git@github.com:<akun>/titian-livekit.git
   git push -u origin main
   ```
2. Railway → **New Project** → **GitHub Repository** → pilih repo itu. Railway membaca `railway.json` dan membangun dari `Dockerfile`.
3. Service → tab **Variables**, tambahkan:

   | Variabel | Isi |
   | --- | --- |
   | `LIVEKIT_API_KEY` | bebas, mis. `pareprod` |
   | `LIVEKIT_API_SECRET` | acak, **≥ 32 karakter** (mis. `openssl rand -hex 32`) |
   | `WEBHOOK_URL` | `https://api.titianasa.com/webhooks/livekit` (untuk dev: lihat di bawah) |

4. Tab **Settings → Networking**:
   - **Public Networking → Generate Domain** dengan target port **7880** → `https://<nama>.up.railway.app` (Railway memberi HTTPS/WSS).
   - **TCP Proxy → Add** dengan application port **7882** (bukan 7881). Railway memberi `host:port` acak — catat saja, tidak perlu disalin.
5. **Redeploy** service (variabel `RAILWAY_TCP_PROXY_*` baru ada setelah TCP Proxy dibuat). Di **Deployments → Logs**, baris pertama harus:
   `ICE/TCP: klien -> <ip>:<port> (proxy Railway) -> :7882 -> LiveKit :<port>`.
   Bila muncul `PERINGATAN: TCP Proxy Railway belum ada`, ulangi langkah 4 lalu redeploy.
6. Cek: `curl https://<nama>.up.railway.app` → `OK`.

## Sambungkan ke backend

Di lingkungan backend (`.env` / variabel deploy), lalu restart backend:

```
LIVEKIT_URL=wss://<nama>.up.railway.app
LIVEKIT_API_KEY=<sama dengan Railway>
LIVEKIT_API_SECRET=<sama dengan Railway>
```

FE (`pare.titianasa.com` atau localhost) tidak perlu diubah: ia memakai `livekit_url` yang dikirim backend.

**Dev dan prod.** Satu LiveKit hanya punya satu `WEBHOOK_URL`. Cara paling bersih: **satu service Railway per lingkungan** (dua service dari repo yang sama,
masing-masing dengan `WEBHOOK_URL`, API key, dan domain sendiri) — dev → backend dev, prod → `api.titianasa.com`.
Backend yang jalan di laptop tidak bisa menerima webhook dari internet kecuali lewat terowongan (mis. `cloudflared tunnel --url http://localhost:8090`,
lalu isi `WEBHOOK_URL` dengan alamatnya + `/webhooks/livekit`).

Yang butuh webhook: status sesi `ended`, waktu keluar peserta, dan pelepasan kunci "satu panggilan per pemain" saat browser ditutup mendadak.
Tanpa webhook, panggilan dan suara tetap jalan.

## Uji

Dua pemain (dua akun, dua browser) yang sudah saling berbalas chat dan menyetujui pemakaian suara: buka chat personal → 📞 → **Jawab** di sisi lain → bicara.
Di Chrome, `chrome://webrtc-internals` → koneksi ke domain Railway: kandidat terpilih harus `tcp` dan byte terkirim/diterima terus bertambah.

## Cara kerjanya (bila perlu men-debug)

Railway memberi port publik TCP yang **dipilih Railway** (mis. `xyz.proxy.rlwy.net:15140`) dan meneruskannya ke *application port* (7882).
Klien WebRTC harus menyambung persis ke `IP:port publik` itu, sehingga `entrypoint.sh`:
1. mengatur LiveKit mendengarkan dan **mengiklankan** port publik itu (`rtc.tcp_port`) dan IP proxy (`rtc.node_ip`, dicari dari `RAILWAY_TCP_PROXY_DOMAIN`);
2. menjalankan `socat` yang meneruskan application port 7882 → port tsb di dalam kontainer (lewat IP kontainer, bukan `127.0.0.1` — LiveKit mengabaikan ICE dari loopback).

Jalur ini sudah diuji lokal (kontainer + Docker mensimulasikan proxy, UDP diblokir, dua Chrome nyata, audio dua arah lewat TCP, webhook sampai ke backend).
**Belum** diuji di Railway sungguhan.

| Gejala | Kemungkinan penyebab |
| --- | --- |
| Log: `PERINGATAN: TCP Proxy Railway belum ada` | TCP Proxy belum dibuat, atau belum redeploy setelahnya |
| "Menyambung…" lalu terputus | domain publik belum dibuat / target port bukan 7880 / `LIVEKIT_URL` bukan `wss://` |
| Tersambung, ada nama lawan bicara, **tidak ada suara** | application port TCP Proxy bukan 7882; atau `RAILWAY_TCP_PROXY_*` kosong → redeploy |
| 401 di `/webhooks/livekit` (log backend) | API secret backend ≠ Railway |
| Tidak ada webhook masuk | `WEBHOOK_URL` salah/kosong atau backend tak terjangkau dari internet |
| Container gagal start: `LIVEKIT_API_SECRET harus minimal 32 karakter` | isi ulang secret yang lebih panjang |

Rencana B bila Railway bermasalah: **LiveKit Cloud** (paket gratis) — ganti tiga variabel backend di atas dan isi URL webhook di dashboard-nya (media lewat UDP).
