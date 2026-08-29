#!/bin/bash
# Скачивание .gguf в контекст сборки с докачкой. Сеть до HuggingFace
# нестабильна (разрывы на больших файлах), поэтому качаем не в docker build,
# а здесь: до 40 попыток, `curl -C -` продолжает с места разрыва.
#
# Использование:
#   ./download.sh <URL .gguf> [ожидаемый размер в байтах]
#
# Файл кладётся рядом с этим скриптом (isolated/models/), имя — из URL.
# Ожидаемый размер берётся из заголовка `x-linked-size` HuggingFace
# (curl -sI -L <URL> | grep -i x-linked-size); без него проверка на
# целостность не делается, только на «файл непустой».
set -u
URL="${1:?нужен URL .gguf}"
EXPECT="${2:-}"
OUT="$(dirname "$0")/$(basename "${URL%%\?*}")"

for i in $(seq 1 40); do
    cur=$(stat -c%s "$OUT" 2>/dev/null || echo 0)
    echo "[$(date +%T)] попытка $i: уже $cur${EXPECT:+ / $EXPECT} байт"
    if [ -n "$EXPECT" ] && [ "$cur" -eq "$EXPECT" ]; then
        echo "GOT $OUT ($cur байт)"; exit 0
    fi
    curl -fL -C - --connect-timeout 30 --max-time 900 --retry 2 -o "$OUT" "$URL" 2>&1
    rc=$?
    if [ $rc -eq 33 ]; then  # сервер отверг Range — начинаем заново
        echo "Range отклонён (файл, возможно, уже цел) — проверяем с нуля"
        rm -f "$OUT"
    fi
    sleep 3
done

cur=$(stat -c%s "$OUT" 2>/dev/null || echo 0)
if [ -n "$EXPECT" ]; then
    [ "$cur" -eq "$EXPECT" ] && { echo "GOT $OUT ($cur байт)"; exit 0; }
    echo "НЕ СКАЧАНО: $cur / $EXPECT байт после 40 попыток" >&2
else
    [ -s "$OUT" ] && { echo "GOT $OUT ($cur байт, размер не сверялся)"; exit 0; }
    echo "НЕ СКАЧАНО: файл пуст после 40 попыток" >&2
fi
exit 1
