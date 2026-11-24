#!/usr/bin/env bash
# wifi-diag.sh — sequential Wi-Fi / network benchmark for Linux
# Usage: ./wifi-diag.sh before    (then later)    ./wifi-diag.sh after
# Needs: iw, nmcli, ip, ping, dig, curl. Optional: traceroute, sudo (for full scan).
# Tests run strictly one after another so idle latency is never polluted by load.

TAG="${1:-run}"
OUT="$HOME/wifi-diag-$TAG-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$OUT") 2>&1
hdr(){ echo; echo "=================== $* ==================="; }

IFACE=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')
GW=$(ip route | awk '/^default/{print $3; exit}')
echo "Run: $TAG   Date: $(date)   Iface: ${IFACE:-none}   Gateway: ${GW:-none}"

###############################################################################
hdr "1. WI-FI LINK & RF"
if [ -n "$IFACE" ]; then
  iw dev "$IFACE" link
  echo "--- channel / width ---"
  iw dev "$IFACE" info | grep -E "channel|ssid|txpower"
  echo "--- station stats (tx/rx bitrate incl. MCS/NSS, signal, retries, failures) ---"
  iw dev "$IFACE" station dump | grep -E "signal|bitrate|tx retries|tx failed|beacon loss|expected"
  echo "--- noise / channel busy time (survey, in-use channel) ---"
  iw dev "$IFACE" survey dump | awk '/in use/{p=1} p&&/noise|busy|active|transmit|receive/{print} /Survey/&&!/in use/{p=0}'
  echo "--- interface packet errors ---"
  ip -s link show "$IFACE" | sed -n '3,8p'
  echo "--- nearby networks: APs per channel (2.4 GHz: ch 1-14, 5 GHz: 36+, 6 GHz: via freq) ---"
  nmcli -t -f CHAN,FREQ,SIGNAL,SSID dev wifi list --rescan yes 2>/dev/null > /tmp/scan.$$
  awk -F: '{band=($2+0<3000)?"2.4":(($2+0<5900)?"5":"6"); c[band" GHz ch "$1]++}
           END{for(k in c) print c[k]" APs  ->  "k}' /tmp/scan.$$ | sort -k5,5 -k7,7n
  echo "--- strongest competing APs (signal %) ---"
  sort -t: -k3 -nr /tmp/scan.$$ | head -12 | awk -F: '{printf "ch %-4s %s MHz  sig %s%%  %s\n",$1,$2,$3,$4}'
  rm -f /tmp/scan.$$
else
  echo "No Wi-Fi interface found (wired?)."
fi

###############################################################################
hdr "2. IDLE LATENCY & STABILITY"
echo "--- gateway ($GW) x30 ---"
ping -c 30 -i 0.2 "$GW" | tail -3
echo "--- 1.1.1.1 x30 ---"
ping -c 30 -i 0.2 1.1.1.1 | tail -3
if ip -6 route | grep -q '^default'; then
  echo "--- IPv6 2606:4700:4700::1111 x30 ---"
  ping -6 -c 30 -i 0.2 2606:4700:4700::1111 | tail -3
else
  echo "IPv6: no default route (inactive)"
fi
echo "--- 5-hop traceroute ---"
if command -v traceroute >/dev/null; then traceroute -n -m 5 -w 2 1.1.1.1
else tracepath -n -m 5 1.1.1.1; fi

echo "--- VPN / proxy / tunnels ---"
ip -o link | grep -Ei 'tun|tap|wg|tailscale|ppp|zt' || echo "no tunnel interfaces"
env | grep -i _proxy || echo "no proxy env vars"
echo "--- top sockets / apps using network (current connections) ---"
ss -s | head -3
ss -tunp 2>/dev/null | awk 'NR>1{print $NF}' | sort | uniq -c | sort -nr | head -5
echo "--- recent Wi-Fi disconnect/roam events (24h) ---"
journalctl --since "24 hours ago" 2>/dev/null | grep -Ei 'disassoc|deauth|roam|CTRL-EVENT-DISCONNECTED|beacon loss|reason=' | tail -15 || true

###############################################################################
hdr "3. DNS LATENCY (uncached: random subdomain forces recursion)"
echo "--- configured resolvers ---"
resolvectl dns 2>/dev/null | head -5
grep ^nameserver /etc/resolv.conf
dns_avg(){ # $1 = server
  local tot=0 n=0 t
  for i in 1 2 3 4 5; do
    t=$(dig @"$1" "r$RANDOM$RANDOM.google.com" A +tries=1 +time=3 2>/dev/null | awk '/Query time/{print $4}')
    [ -n "$t" ] && { tot=$((tot+t)); n=$((n+1)); }
  done
  [ $n -gt 0 ] && echo "$1: avg $((tot/n)) ms ($n/5 ok)" || echo "$1: no answer"
}
for s in "$GW" 1.1.1.1 8.8.8.8; do dns_avg "$s"; done
for s in $(grep ^nameserver /etc/resolv.conf | awk '{print $2}' | grep -v '^127\.'); do dns_avg "$s"; done

###############################################################################
hdr "4. THROUGHPUT & BUFFERBLOAT"
echo "--- idle latency reference (10 pings) ---"
ping -c 10 -i 0.2 1.1.1.1 | tail -1

echo "--- DOWNLOAD (15s, Cloudflare) with concurrent ping ---"
ping -c 12 -i 1 1.1.1.1 > /tmp/ping_dl.$$ &
curl -s -o /dev/null --max-time 15 -w "Downlink: %{speed_download} B/s\n" \
  "https://speed.cloudflare.com/__down?bytes=500000000" | awk '{printf "Downlink: %.1f Mbit/s\n",$2*8/1e6}'
wait; tail -1 /tmp/ping_dl.$$

echo "--- UPLOAD (15s) with concurrent ping ---"
head -c 100000000 /dev/zero > /tmp/up.$$
ping -c 12 -i 1 1.1.1.1 > /tmp/ping_ul.$$ &
curl -s -o /dev/null --max-time 15 -X POST --data-binary @/tmp/up.$$ \
  -w "Uplink: %{speed_upload} B/s\n" "https://speed.cloudflare.com/__up" | awk '{printf "Uplink: %.1f Mbit/s\n",$2*8/1e6}'
wait; tail -1 /tmp/ping_ul.$$

rtt(){ awk -F'/' '/rtt|round-trip/{print $5}' "$1"; }
DL=$(rtt /tmp/ping_dl.$$); UL=$(rtt /tmp/ping_ul.$$)
echo "Loaded avg latency  down: ${DL:-?} ms   up: ${UL:-?} ms"
for v in "$DL" "$UL"; do [ -n "$v" ] && awk -v l="$v" 'BEGIN{printf "  approx RPM (60000/ms): %.0f\n", 60000/l}'; done
rm -f /tmp/ping_dl.$$ /tmp/ping_ul.$$ /tmp/up.$$

echo "--- ECN / L4S / qdisc ---"
echo "tcp_ecn=$(sysctl -n net.ipv4.tcp_ecn 2>/dev/null)  (0=off,1=on,2=only if requested by peer)"
echo "congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)  (prague = L4S-capable)"
tc qdisc show dev "${IFACE:-$(ip route | awk '/^default/{print $5; exit}')}" 2>/dev/null | head -2

echo; echo "Report saved to: $OUT"
