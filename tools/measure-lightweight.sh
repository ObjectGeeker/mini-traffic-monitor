#!/bin/bash
# 轻量性验收（NFR-1/2/3）：周期采样 RSS 与 CPU，输出 CSV 与摘要
# 用法: ./tools/measure-lightweight.sh [时长秒 默认86400=24h] [采样间隔秒 默认30] [输出csv 默认/tmp/mtm-lightweight.csv]
DURATION=${1:-86400}
INTERVAL=${2:-30}
OUT=${3:-/tmp/mtm-lightweight.csv}

PID=$(pgrep -f "MiniTrafficMonitor.app/Contents/MacOS" | head -1)
if [ -z "$PID" ]; then echo "app 未运行"; exit 1; fi

echo "epoch,rss_kb,cpu_pct" > "$OUT"
END=$(( $(date +%s) + DURATION ))
FIRST=""; LAST=""; MAXCPU=0
while [ "$(date +%s)" -lt "$END" ]; do
  LINE=$(ps -o rss=,%cpu= -p "$PID" 2>/dev/null)
  [ -z "$LINE" ] && break
  RSS=$(echo "$LINE" | awk '{print $1}')
  CPU=$(echo "$LINE" | awk '{print $2}')
  echo "$(date +%s),$RSS,$CPU" >> "$OUT"
  [ -z "$FIRST" ] && FIRST=$RSS
  LAST=$RSS
  MAXCPU=$(python3 -c "print(max($MAXCPU, $CPU))")
  sleep "$INTERVAL"
done

GROWTH=$(( LAST - FIRST ))
echo "采样结束 pid=$PID"
echo "  首 RSS = ${FIRST} KB   末 RSS = ${LAST} KB   增长 = ${GROWTH} KB"
echo "  生命周期平均 CPU = ${MAXCPU}%  （NFR-3 要求 <= 0.3%）"
echo "  NFR-1 要求 RSS <= 25600 KB；NFR-2 要求 24h 增长趋近 0"
echo "  明细: $OUT"
