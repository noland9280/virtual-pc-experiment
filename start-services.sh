#!/bin/bash
# (Re)starts the manually-managed services that don't survive rebuilds or
# occasional crashes: the ffmpeg audio stream (port 8998) and the tiny HTTP
# server that serves audio.html/viewer.html (port 8999).
# Safe to run anytime - it only starts what isn't already running.
REPO=/workspaces/literate-octo-fortnight

echo "=== サービス起動チェック ==="

# ffmpegが何らかの理由(リビルド時のpostCreateCommand失敗など)で
# 消えていることがあるため、無ければここで自己修復する。
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[修復] ffmpegが見つからないためインストールします..."
  sudo apt-get update -qq && sudo apt-get install -y ffmpeg pulseaudio-utils
  if command -v ffmpeg >/dev/null 2>&1; then
    echo "[修復完了] ffmpegをインストールしました"
  else
    echo "[失敗] ffmpegのインストールに失敗しました"
  fi
fi

if ss -tln 2>/dev/null | grep -q ':8998 '; then
  echo "[OK] 音声配信(8998)はすでに動作中です"
else
  nohup bash -c 'while true; do ffmpeg -fflags nobuffer -flags low_delay -f pulse -i auto_null.monitor -acodec libmp3lame -b:a 64k -ar 44100 -ac 2 -flush_packets 1 -f mp3 -listen 1 http://0.0.0.0:8998/stream.mp3; sleep 2; done' > /tmp/audio-stream.log 2>&1 &
  disown
  sleep 2
  if ss -tln 2>/dev/null | grep -q ':8998 '; then
    echo "[起動] 音声配信(8998)を起動しました"
  else
    echo "[失敗] 音声配信(8998)の起動に失敗しました。/tmp/audio-stream.log を確認してください"
  fi
fi

if ss -tln 2>/dev/null | grep -q ':8999 '; then
  echo "[OK] 音声ページ配信(8999)はすでに動作中です"
else
  nohup python3 -m http.server 8999 --directory "$REPO" > /tmp/http8999.log 2>&1 &
  disown
  sleep 1
  if ss -tln 2>/dev/null | grep -q ':8999 '; then
    echo "[起動] 音声ページ配信(8999)を起動しました"
  else
    echo "[失敗] 音声ページ配信(8999)の起動に失敗しました。/tmp/http8999.log を確認してください"
  fi
fi

echo ""
echo "完了。ブラウザで開く: https://<あなたのcodespace名>-8999.app.github.dev/audio.html"
