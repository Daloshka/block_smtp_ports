#!/usr/bin/env bash
set -u  # без -e, чтобы не падал на частичных ошибках
TIMEOUT=${TIMEOUT:-3}

PORTS=(25 465 587 2525 2465 2587 10025 8025 25025 24)
HOSTS_DIRECT=(
  portquiz.net smtp.gmail.com gmail-smtp-in.l.google.com
  aspmx.l.google.com alt1.aspmx.l.google.com alt2.aspmx.l.google.com
  alt3.aspmx.l.google.com alt4.aspmx.l.google.com
  smtp.office365.com smtp-mail.outlook.com outlook.office365.com
  smtp.sendgrid.net smtp.mailgun.org
  email-smtp.eu-west-1.amazonaws.com email-smtp.us-east-1.amazonaws.com
  smtp.yandex.ru smtp.mail.ru
)
MX_DOMAINS=(gmail.com outlook.com yahoo.com icloud.com yandex.ru mail.ru)

have(){ command -v "$1" >/dev/null 2>&1; }

resolve_all_ips(){
  local name="$1"
  if have getent; then getent ahosts "$name" | awk '{print $1}' | sort -u; return; fi
  if have host;   then host -t A "$name" 2>/dev/null|awk '/has address/{print $4}'; host -t AAAA "$name" 2>/dev/null|awk '/IPv6/{print $5}'; return; fi
  if have dig;    then dig +short A "$name"; dig +short AAAA "$name"; return; fi
  echo ""  # нет резолвера — вернём пусто
}

mx_hosts(){
  local d="$1"
  if have dig;  then dig +short MX "$d" | awk '{print $2}' | sed 's/\.$//' | sort -u; return; fi
  if have host; then host -t MX "$d" 2>/dev/null | awk '{print $NF}' | sed 's/\.$//' | sort -u; return; fi
  echo ""
}

probe(){
  local ip="$1" port="$2"
  if have nc; then
    local fam=""; [[ "$ip" == *:* ]] && fam="-6" || fam="-4"
    timeout "$TIMEOUT" nc $fam -z -w "$TIMEOUT" "$ip" "$port" >/dev/null 2>&1
    return $?
  fi
  # Фолбэк на bash /dev/tcp
  timeout "$TIMEOUT" bash -lc ":</dev/tcp/$ip/$port" >/dev/null 2>&1
}

printf "%s\n" "== Route sanity ==" \
              "$(ip route 2>/dev/null | awk '/^default/{print $0}')" \
              "------------------------------"

any_allow=0

echo "== DIRECT HOSTS (A/AAAA of known SMTP/relays) =="
for host in "${HOSTS_DIRECT[@]}"; do
  mapfile -t ips < <(resolve_all_ips "$host")
  if ((${#ips[@]}==0)); then printf "DNS fail or no resolver: %s\n" "$host"; continue; fi
  for port in "${PORTS[@]}"; do
    ok=0
    for ip in "${ips[@]}"; do
      [[ -z "$ip" ]] && continue
      if probe "$ip" "$port"; then ok=1; break; fi
    done
    printf "%-34s" "${host}:${port} "
    if ((ok)); then echo "ALLOW ❌  ${host}:${port}"; any_allow=1; else echo "BLOCK ✅  ${host}:${port}"; fi
  done
done
echo "------------------------------"

echo "== MX CHECK (25/tcp direct) =="
for d in "${MX_DOMAINS[@]}"; do
  mapfile -t mxs < <(mx_hosts "$d")
  (( ${#mxs[@]}==0 )) && { printf "No MX: %s\n" "$d"; continue; }
  for mx in "${mxs[@]}"; do
    mapfile -t ips < <(resolve_all_ips "$mx")
    (( ${#ips[@]}==0 )) && { printf "%-34s%s\n" "${mx}:25 " "DNS fail"; continue; }
    ok=0
    for ip in "${ips[@]}"; do
      [[ -z "$ip" ]] && continue
      if probe "$ip" 25; then ok=1; break; fi
    done
    printf "%-34s" "${mx}:25 "
    if ((ok)); then echo "ALLOW ❌  ${mx}:25"; any_allow=1; else echo "BLOCK ✅  ${mx}:25"; fi
  done
done
echo "------------------------------"

echo "== Sanity (443 must be ALLOW) =="
for h in google.com cloudflare.com fast.com; do
  mapfile -t ips < <(resolve_all_ips "$h")
  ok=0; for ip in "${ips[@]}"; do [[ -z "$ip" ]] && continue; if probe "$ip" 443; then ok=1; break; fi; done
  if ((ok)); then echo "ALLOW ✅  ${h}:443"; else echo "BLOCK ❌  ${h}:443 (unexpected)"; fi
done
echo "------------------------------"

if ((any_allow)); then
  echo "❌ НАЙДЕНЫ ДЫРЫ: исходящий SMTP где-то доступен."; exit 1
else
  echo "✅ ВСЁ ЖЁСТКО ЗАКРЫТО: исходящий SMTP заблокирован на всех проверках."; exit 0
fi
