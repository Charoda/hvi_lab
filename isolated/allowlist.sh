#!/usr/bin/env bash
# Режим "белый список": исходящие соединения только на DNS и на разрешённые
# домены. Исправляет типовую ошибку `iptables -d domain.name`:
# iptables принимает только IP/сети, поэтому домены резолвим сами и
# разрешаем ВСЕ полученные адреса (у CDN их несколько).
set -u

# 1. Служебный трафик: DNS и loopback
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# 2. Белый список доменов (те же, что использовались в раннем варианте
#    run_isolated.sh, плюс CDN-хвосты GitHub и yarn)
DOMAINS="
github.com
api.github.com
codeload.github.com
objects.githubusercontent.com
registry.npmjs.org
npmjs.org
registry.yarnpkg.com
unpkg.com
pypi.org
files.pythonhosted.org
huggingface.co
openrouter.ai
"

# Дополнительные домены от оркестратора (например, эндпоинт LLM-провайдера
# проверяемого агента — передаётся через переменную окружения EXTRA_DOMAINS,
# домены через пробел/перевод строки).
if [ -n "${EXTRA_DOMAINS:-}" ]; then
    DOMAINS="$DOMAINS $EXTRA_DOMAINS"
fi

allowed=0
for d in $DOMAINS; do
    # ahostsv4 — только IPv4: iptables (в отличие от ip6tables) IPv6 не понимает
    for ip in $(getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | sort -u); do
        iptables -A OUTPUT -d "$ip" -j ACCEPT
        allowed=$((allowed + 1))
    done
done

# 3. Всё остальное — запрещено
iptables -A OUTPUT -j DROP
echo "allowlist: разрешено ${allowed} адресов для доменов: $(echo $DOMAINS | tr '\n' ' ')"
