#!/bin/zsh
# Samples CPU and memory of the running AINCRAD process: measure_idle.sh [seconds] (default 300).
set -euo pipefail
secs=${1:-300}
pid=$(pgrep -x AINCRAD | head -1) || { echo "AINCRAD is not running"; exit 1; }
samples=$(( secs / 5 + 1 ))
echo "Sampling pid $pid for ${secs}s..."
top -l $samples -s 5 -pid $pid -stats pid,cpu,mem,rsize 2>/dev/null \
  | awk -v pid=$pid '$1==pid { n++; if (n==1) next; c=$2+0; cpu+=c; if (c>max) max=c; mem=$3 }
      END { if (n>1) printf "samples=%d  avg CPU=%.2f%%  max CPU=%.1f%%  memory=%s\n", n-1, cpu/(n-1), max, mem }'
