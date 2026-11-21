#!/usr/bin/env bash
# =====================================================================
# Colabgaming - desktop game-streaming trong container (không systemd)
#   Sunshine (gói .deb, server stream) + Moonlight Web (xem trong trình duyệt)
#   + Xvfb + Openbox + LXDE panel (lxpanel) + Cloudflare Tunnel
#   + thư viện GPU NVIDIA (Tesla T4) qua EGL / VirtualGL
#
# Dùng:  ./Colabgaming.sh user | install | install-stream | install-gpu | install-apps
#                         | setup | start | stop | restart | status | url | pin <PIN> | gpu | logs [service]
#
# Nếu chạy bằng root, script tự tạo user có quyền sudo (mặc định "remote"),
# rồi tự chuyển sang user đó để chạy lệnh (install, start, ...).
#
# Ngôn ngữ của script (thông báo, hướng dẫn):
#   LANG=vi ./Colabgaming.sh ...     Tiếng Việt          (hoặc RD_LANG=vi)
#   LANG=us ./Colabgaming.sh ...     English             (hoặc RD_LANG=us)
#   Không đặt thì giữ lựa chọn lần trước (mặc định: us).
#
# Biến môi trường (tùy chọn):
#   RD_USER            tên user sẽ tạo/chuyển sang (mặc định: remote)
#   RD_USER_PASSWORD   mật khẩu của user đó (mặc định: quocanhh)
#   RD_AS_ROOT=1       không chuyển user, chạy thẳng bằng root
#   VERBOSE=1          hiện toàn bộ log cài đặt (mặc định ẩn, ghi vào ~/.remote-desktop/log/install.log)
#   RESOLUTION         độ phân giải màn hình ảo VÀ của stream (mặc định 1280x720; 1920x1080 tốn CPU gấp ~2,25 lần)
#   STREAM_FPS         FPS stream mặc định trong Moonlight Web (mặc định 30; 60 tốn CPU gấp đôi)
#   STREAM_BITRATE     bitrate mặc định (kbps) trong Moonlight Web (mặc định 6000; thấp hơn thì nhẹ cho đường truyền/cloudflared)
#   WEB_PORT           cổng Moonlight Web trên localhost (mặc định 6080; tránh 8080 vì Colab dùng)
#   SUNSHINE_USER      tài khoản web UI của Sunshine (mặc định: sunshine)
#   SUNSHINE_PASSWORD  mật khẩu web UI của Sunshine (mặc định: quocanhh; lưu lại cho lần sau)
#   MOONLIGHT_USER     tài khoản admin Moonlight Web tự tạo khi start (mặc định: admin)
#   MOONLIGHT_PASSWORD mật khẩu của nó (mặc định: quocanhh; NÊN ĐỔI vì URL công khai; lưu lại cho lần sau)
#   APT_MIRROR         ép dùng một mirror apt, ví dụ https://mirrors.edge.kernel.org/ubuntu/ (mặc định: tự dò khi
#                      archive.ubuntu.com không tới được, như trên Kaggle); đặt APT_MIRROR=skip để không đụng vào apt
#   SUNSHINE_WAIT      số giây chờ Sunshine sẵn sàng khi start (mặc định 45)
#   SUNSHINE_VERSION   tag Sunshine, ví dụ v2026.914.233613 (mặc định: bản mới nhất)
#   SUNSHINE_CODECS    h264 (mặc định: Sunshine chỉ quảng cáo H.264, tránh lỗi "VideoDecoder ... Decoding error" khi
#                      trình duyệt nhận H.265/AV1) hoặc all (cho phép cả H.265 và AV1)
#   SUNSHINE_DEB_FLAVOR  bản .deb dùng cho Ubuntu nào: ubuntu22.04 (mặc định) hoặc ubuntu24.04
#   SUNSHINE_DEB_URL   ép dùng đúng link .deb này (bỏ qua SUNSHINE_VERSION / SUNSHINE_DEB_FLAVOR)
#   MOONLIGHT_VERSION  tag Moonlight Web, ví dụ v3.0.2 (mặc định: bản mới nhất)
#   MOONLIGHT_TRANSPORT  Data Transport mặc định của Moonlight Web: websocket (mặc định, hợp Cloudflare) hoặc auto
#   TURN_URL / TURN_USERNAME / TURN_CREDENTIAL   (tùy chọn) TURN server cho WebRTC, ví dụ TURN_URL=turn:host:443?transport=tcp
#   CF_PROTOCOL        giao thức cloudflared: http2 (mặc định) hoặc quic
#   CF_TOKEN           token Cloudflare Tunnel đã đặt tên (trống -> quick tunnel *.trycloudflare.com)
#   VGL_VERSION        phiên bản VirtualGL (mặc định 3.1.1)
#   POLYMC_VERSION     phiên bản PolyMC (mặc định 7.0)
#   SKIP_APPS=1        khi 'install' thì bỏ qua Chromium + Java 25 + PolyMC
#
# Chạy ứng dụng bằng GPU:  gpurun <lệnh>      ví dụ:  gpurun glxgears
# Ứng dụng:  chromium-rd (Chromium) | polymc | gpurun polymc   (cũng có trong menu chuột phải)
# =====================================================================
set -u

DISP_NUM=20            # màn hình ảo :20
RESOLUTION="${RESOLUTION:-1366x768}"
WEB_PORT="${WEB_PORT:-6080}"
CF_TOKEN="${CF_TOKEN:-}"
CF_PROTOCOL="${CF_PROTOCOL:-http2}"
VERBOSE="${VERBOSE:-0}"
RD_USER="${RD_USER:-Quahnah}"
RD_USER_PASSWORD="${RD_USER_PASSWORD:-quocanhh}"

# ---------------------------------------------------------------------
# Ngôn ngữ của script: RD_LANG=vi|us hoặc LANG=vi|us; không đặt thì dùng lựa chọn đã lưu
RD_LANG_SET=""
case "${RD_LANG:-}" in
  vi*|VI*) RD_LANG_SET=vi ;;
  us*|US*|en*|EN*) RD_LANG_SET=us ;;
esac
if [ -z "$RD_LANG_SET" ]; then
  case "${LANG:-}" in
    vi|vi_VN|vi_VN.UTF-8) RD_LANG_SET=vi ;;
    us|en) RD_LANG_SET=us ;;
  esac
fi
if [ -n "$RD_LANG_SET" ]; then
  RD_LANG="$RD_LANG_SET"
elif [ -r "$HOME/.remote-desktop/lang" ]; then
  RD_LANG="$(cat "$HOME/.remote-desktop/lang" 2>/dev/null)"
elif [ -r /etc/colabgaming.lang ]; then
  RD_LANG="$(cat /etc/colabgaming.lang 2>/dev/null)"
else
  RD_LANG=us
fi
case "$RD_LANG" in vi|us) ;; *) RD_LANG=us ;; esac
if [ -n "$RD_LANG_SET" ]; then      # nhớ lựa chọn cho lần sau
  [ "$(id -u)" -eq 0 ] && echo "$RD_LANG" > /etc/colabgaming.lang 2>/dev/null
  mkdir -p "$HOME/.remote-desktop" 2>/dev/null && echo "$RD_LANG" > "$HOME/.remote-desktop/lang" 2>/dev/null
fi
export LANG=C.UTF-8                 # chỉ cho chính script này (tránh cảnh báo locale khi LANG=vi)

# t "<tiếng Việt>" "<English>"  -> in theo ngôn ngữ đã chọn
t() { if [ "$RD_LANG" = "vi" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2; }
L() { log "$(t "$1" "$2")"; }       # log song ngữ
E() { err "$(t "$1" "$2")"; }       # lỗi song ngữ

# ---------------------------------------------------------------------
# Tạo user có quyền sudo (cần chạy bằng root)
ensure_user() {
  if [ "$(id -u)" -ne 0 ]; then E "Cần chạy bằng root để tạo user." "Must run as root to create the user."; return 1; fi

  if ! command -v sudo >/dev/null 2>&1; then
    L "Cài sudo..." "Installing sudo..."
    env DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1
    env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo >/dev/null 2>&1 \
      || { E "Không cài được sudo." "Could not install sudo."; return 1; }
  fi

  if id "$RD_USER" >/dev/null 2>&1; then
    L "User '$RD_USER' đã tồn tại." "User '$RD_USER' already exists."
  else
    L "Tạo user '$RD_USER'..." "Creating user '$RD_USER'..."
    useradd -m -s /bin/bash "$RD_USER" || { E "useradd lỗi." "useradd failed."; return 1; }
    echo "$RD_USER:$RD_USER_PASSWORD" | chpasswd
  fi

  usermod -aG sudo "$RD_USER" 2>/dev/null
  for g in video render audio; do
    getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$RD_USER" 2>/dev/null
  done

  # Không hỏi mật khẩu khi dùng sudo (script cần chạy apt tự động)
  mkdir -p /etc/sudoers.d
  echo "$RD_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$RD_USER"
  chmod 440 "/etc/sudoers.d/90-$RD_USER"
}

# Chuyển sang user rồi chạy lại chính script này với cùng tham số
reexec_as_user() {
  ensure_user || exit 1
  local home dst self envs v
  home="$(getent passwd "$RD_USER" | cut -d: -f6)"
  dst="$home/Colabgaming.sh"
  self="$(readlink -f "$0")"
  if [ "$self" != "$dst" ]; then
    install -o "$RD_USER" -g "$(id -gn "$RD_USER")" -m 0755 "$self" "$dst"
  fi

  # Giữ lại các biến cấu hình và PATH (Colab có nvidia-smi ở thư mục riêng)
  envs="export PATH=$(printf '%q' "$PATH"):\$PATH; "
  for v in RD_LANG_SET STREAM_FPS STREAM_BITRATE SUNSHINE_CODECS SUNSHINE_DEB_URL SUNSHINE_DEB_FLAVOR APT_MIRROR MOONLIGHT_USER MOONLIGHT_PASSWORD MOONLIGHT_TRANSPORT TURN_URL TURN_USERNAME TURN_CREDENTIAL SUNSHINE_WAIT CF_PROTOCOL WEB_PORT RESOLUTION SUNSHINE_USER SUNSHINE_PASSWORD SUNSHINE_VERSION MOONLIGHT_VERSION CF_TOKEN VGL_VERSION POLYMC_VERSION SKIP_APPS VERBOSE; do
    if [ -n "${!v-}" ]; then
      if [ "$v" = "RD_LANG_SET" ]; then envs+="export RD_LANG=$(printf '%q' "${!v}"); "
      else envs+="export $v=$(printf '%q' "${!v}"); "; fi
    fi
  done

  # Ghi lại vị trí nvidia-smi thật (user thường có thể không có thư mục này trong PATH)
  command -v nvidia-smi >/dev/null 2>&1 && command -v nvidia-smi > /etc/remote-desktop-nvidia-smi.path
  [ -n "${LD_LIBRARY_PATH:-}" ] && printf '%s\n' "$LD_LIBRARY_PATH" > /etc/remote-desktop-ld.path

  L "Chuyển sang user '$RD_USER'..." "Switching to user '$RD_USER'..."
  exec su - "$RD_USER" -c "${envs}bash $(printf '%q' "$dst") $(printf '%q ' "$@")"
}

# Chạy bằng root -> tự tạo user và chuyển sang (trừ lệnh 'user' và khi RD_AS_ROOT=1)
case "${1:-}" in
  install|install-stream|install-gpu|install-apps|setup|start|stop|restart|status|url|pin|gpu|logs)
    if [ "$(id -u)" -eq 0 ] && [ "${RD_AS_ROOT:-0}" != "1" ]; then
      reexec_as_user "$@"
    fi
    ;;
esac

# ---------------------------------------------------------------------
BASE="${HOME}/.remote-desktop"
RUN="$BASE/run"; LOG="$BASE/log"; BIN="$BASE/bin"
mkdir -p "$RUN" "$LOG" "$BIN"
INSTALL_LOG="$LOG/install.log"

SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null && SUDO="sudo"
# Sunshine cài bằng gói .deb -> chương trình nằm ở /usr/bin/sunshine
SUN_BIN="/usr/bin/sunshine"
# Timeout ngắn + thử lại ít: nếu kho apt không tới được thì báo lỗi nhanh thay vì treo hàng chục phút
APT="env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20"

# Tài khoản web UI của Sunshine: dùng giá trị đặt lần này, nếu không thì giá trị đã lưu, mặc định sunshine / quocanhh
SUN_USER="${SUNSHINE_USER:-}"; SUN_PASS="${SUNSHINE_PASSWORD:-}"
if { [ -z "$SUN_USER" ] || [ -z "$SUN_PASS" ]; } && [ -r "$BASE/sunshine.cred" ]; then
  _saved="$(cat "$BASE/sunshine.cred" 2>/dev/null)"
  [ -n "$SUN_USER" ] || SUN_USER="${_saved%%:*}"
  [ -n "$SUN_PASS" ] || SUN_PASS="${_saved#*:}"
fi
SUN_USER="${SUN_USER:-sunshine}"; SUN_PASS="${SUN_PASS:-quocanhh}"

# Tài khoản admin Moonlight Web: dùng giá trị đặt lần này, nếu không thì giá trị đã lưu, mặc định admin / quocanhh
MOON_USER="${MOONLIGHT_USER:-}"; MOON_PASS="${MOONLIGHT_PASSWORD:-}"
if { [ -z "$MOON_USER" ] || [ -z "$MOON_PASS" ]; } && [ -r "$BASE/moonlight.cred" ]; then
  _msaved="$(cat "$BASE/moonlight.cred" 2>/dev/null)"
  [ -n "$MOON_USER" ] || MOON_USER="${_msaved%%:*}"
  [ -n "$MOON_PASS" ] || MOON_PASS="${_msaved#*:}"
fi
MOON_USER="${MOON_USER:-admin}"; MOON_PASS="${MOON_PASS:-quocanhh}"

# run "<mô tả>" <lệnh...>  -> ẩn output, ghi vào install.log; lỗi thì in đoạn cuối log
run() {
  local msg="$1"; shift
  log "$msg"
  if [ "$VERBOSE" = "1" ]; then "$@"; return $?; fi
  echo "=== $msg: $* ===" >> "$INSTALL_LOG"
  "$@" >> "$INSTALL_LOG" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    err "$(t "Lỗi khi" "Failed"): $msg (rc=$rc). $(t "Chi tiết" "Details"): $INSTALL_LOG"
    tail -n 15 "$INSTALL_LOG" >&2
  fi
  return "$rc"
}
# R "<vi>" "<us>" <lệnh...>  -> run song ngữ
R() { local m; m="$(t "$1" "$2")"; shift 2; run "$m" "$@"; }

# ---------------------------------------------------------------------
# ---------------------------------------------------------------------
# Một số nền tảng (ví dụ Kaggle) không tới được archive.ubuntu.com / security.ubuntu.com: apt treo rất lâu rồi
# không tải được gói nào. Hàm này kiểm tra nhanh, nếu không tới được thì dò một mirror khác tới được và
# chuyển các nguồn apt của Ubuntu sang mirror đó (sao lưu file gốc thành *.colabgaming.bak).
setup_apt_mirror() {
  [ "${APT_MIRROR:-}" = "skip" ] && return 0
  [ -f /etc/apt/colabgaming.mirror ] && [ -z "${APT_MIRROR:-}" ] && return 0
  local codename cand ok="" f
  codename="$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-noble}")"

  # Kho mặc định có tới được không? Thử 3 lần (một lần mạng chậm không đủ để kết luận là bị chặn)
  if [ -z "${APT_MIRROR:-}" ]; then
    local try
    for try in 1 2 3; do
      if curl -fsS -m 8 -o /dev/null "http://archive.ubuntu.com/ubuntu/dists/$codename/InRelease" 2>/dev/null; then
        return 0                               # kho mặc định tới được, không cần đổi
      fi
      sleep 1
    done
  fi

  L "      Không tới được archive.ubuntu.com, đang dò mirror apt khác..." \
    "      archive.ubuntu.com is unreachable, probing another apt mirror..."
  local candidates=(
    ${APT_MIRROR:+"$APT_MIRROR"}
    "http://us-central1.gce.archive.ubuntu.com/ubuntu/"
    "https://mirrors.edge.kernel.org/ubuntu/"
    "https://mirror.us.leaseweb.net/ubuntu/"
    "https://mirrors.xtom.com/ubuntu/"
    "https://ftp.halifax.rwth-aachen.de/ubuntu/"
    "https://mirrors.ustc.edu.cn/ubuntu/"
    "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
    "https://ftp.sjtu.edu.cn/ubuntu/"
  )
  for cand in "${candidates[@]}"; do
    cand="${cand%/}/"
    if curl -fsS -m 8 -o /dev/null "${cand}dists/${codename}/InRelease" 2>/dev/null; then ok="$cand"; break; fi
  done
  if [ -z "$ok" ]; then
    E "Không tìm được mirror apt nào tới được. Thử đặt APT_MIRROR=<địa chỉ mirror Ubuntu tới được từ máy này>." \
      "No reachable apt mirror found. Try setting APT_MIRROR=<an Ubuntu mirror reachable from this machine>."
    return 1
  fi

  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] || continue
    grep -qE 'ubuntu\.com/ubuntu' "$f" || continue
    [ -f "$f.colabgaming.bak" ] || $SUDO cp -p "$f" "$f.colabgaming.bak"
    $SUDO sed -i -E "s#https?://([a-z0-9.-]+\.)?(archive|security)\.ubuntu\.com/ubuntu/?#${ok}#g" "$f"
  done
  echo "$ok" | $SUDO tee /etc/apt/colabgaming.mirror >/dev/null
  L "      Dùng mirror apt: $ok" "      Using apt mirror: $ok"
  return 0
}

install_all() {
  : > "$INSTALL_LOG"
  L "Log cài đặt: $INSTALL_LOG (đặt VERBOSE=1 nếu muốn xem trực tiếp)" \
    "Install log: $INSTALL_LOG (set VERBOSE=1 to see it live)"

  setup_apt_mirror || exit 1
  R "[1/6] Cập nhật danh sách gói" "[1/6] Updating package lists" $SUDO $APT update -qq || exit 1
  R "[2/6] Cài Xvfb, Openbox, LXDE panel, PulseAudio và công cụ" \
    "[2/6] Installing Xvfb, Openbox, LXDE panel, PulseAudio and tools" \
    $SUDO $APT install -y --no-install-recommends \
    xvfb openbox lxpanel lxmenu-data lxde-icon-theme hicolor-icon-theme \
    xterm lxterminal pcmanfm lxtask dbus-x11 xclip \
    x11-xserver-utils x11-xkb-utils xkb-data xauth \
    fonts-dejavu-core fonts-noto-core pulseaudio pulseaudio-utils \
    curl wget ca-certificates procps psmisc || exit 1

  if ! command -v cloudflared >/dev/null; then
    local a
    case "$(uname -m)" in
      x86_64) a=amd64 ;; aarch64|arm64) a=arm64 ;; armv7l) a=arm ;; *) E "Arch không hỗ trợ" "Unsupported architecture"; exit 1 ;;
    esac
    R "[3/6] Tải cloudflared" "[3/6] Downloading cloudflared" curl -fsSL \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$a" \
      -o /tmp/cloudflared || exit 1
    R "      Cài cloudflared" "      Installing cloudflared" $SUDO install -m 0755 /tmp/cloudflared /usr/local/bin/cloudflared || exit 1
    rm -f /tmp/cloudflared
  else
    L "[3/6] cloudflared đã có." "[3/6] cloudflared already installed."
  fi

  L "[4/6] Sunshine + Moonlight Web" "[4/6] Sunshine + Moonlight Web"
  install_stream || exit 1

  L "[5/6] GPU NVIDIA" "[5/6] NVIDIA GPU"
  install_gpu

  if [ "${SKIP_APPS:-0}" = "1" ]; then
    L "[6/6] Bỏ qua Chromium/Java/PolyMC (SKIP_APPS=1). Cài sau bằng: $0 install-apps" \
      "[6/6] Skipping Chromium/Java/PolyMC (SKIP_APPS=1). Install later with: $0 install-apps"
  else
    L "[6/6] Chromium + Java 25 + PolyMC" "[6/6] Chromium + Java 25 + PolyMC"
    install_apps
  fi
  L "Cài xong. Chạy: $0 start" "Done. Run: $0 start"
}

# ---------------------------------------------------------------------
# Sunshine + Moonlight Web
# Thư viện hệ thống mà Sunshine cần (libpipewire, libgbm, ...) nhưng chưa có trên máy.
# Chạy được nhiều lần: kiểm tra bằng ldd, thiếu thư viện nào thì cài đúng gói tương ứng.
# Luôn được gọi (cả khi Sunshine "đã có") vì lần cài trước có thể bị ngắt giữa chừng.
ensure_sunshine_libs() {
  local bin="$SUN_BIN" missing lib p pkgs
  [ -x "$bin" ] || return 0
  missing="$(ldd "$bin" 2>/dev/null | awk '/not found/{print $1}')"
  [ -n "$missing" ] || return 0
  L "      Sunshine thiếu thư viện hệ thống: $(echo $missing) - đang cài..." \
    "      Sunshine is missing system libraries: $(echo $missing) - installing..."
  setup_apt_mirror || true
  $SUDO $APT update -qq >> "$INSTALL_LOG" 2>&1 || true
  for lib in $missing; do
    case "$lib" in
      libpipewire-0.3.so*)   pkgs="libpipewire-0.3-0t64 libpipewire-0.3-0" ;;
      libgbm.so*)            pkgs="libgbm1" ;;
      libdrm.so*)            pkgs="libdrm2" ;;
      libwayland-client.so*) pkgs="libwayland-client0" ;;
      libX11.so*)            pkgs="libx11-6" ;;
      libasound.so*)         pkgs="libasound2t64 libasound2" ;;
      *)                     pkgs="" ;;
    esac
    for p in $pkgs; do
      echo "=== apt install $p (cho $lib) ===" >> "$INSTALL_LOG"
      if $SUDO $APT install -y --no-install-recommends "$p" >> "$INSTALL_LOG" 2>&1; then break; fi
    done
  done
  $SUDO ldconfig >/dev/null 2>&1
  missing="$(ldd "$bin" 2>/dev/null | awk '/not found/{print $1}')"
  if [ -n "$missing" ]; then
    E "Sunshine VẪN thiếu thư viện: $(echo $missing)" "Sunshine is STILL missing libraries: $(echo $missing)"
    echo "--- apt ($INSTALL_LOG) ---"
    grep -E '^E:|Unable to locate|has no installation candidate|Err:' "$INSTALL_LOG" 2>/dev/null | tail -n 8
    return 1
  fi
  L "      Đã cài đủ thư viện cho Sunshine." "      All libraries for Sunshine are installed."
  return 0
}

install_sunshine() {
  local arch tag ver flavor url assets debname
  if [ -x "$SUN_BIN" ]; then
    L "      Sunshine đã có." "      Sunshine already installed."
    ensure_sunshine_libs || true      # bắt buộc kiểm tra: lần cài trước có thể bị ngắt giữa chừng
    return 0
  fi
  case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) E "Sunshine: arch không hỗ trợ" "Sunshine: unsupported architecture"; return 1 ;; esac

  url="${SUNSHINE_DEB_URL:-}"
  if [ -z "$url" ]; then
    flavor="${SUNSHINE_DEB_FLAVOR:-ubuntu22.04}"
    tag="${SUNSHINE_VERSION:-}"
    if [ -z "$tag" ]; then
      tag="$(curl -sL -o /dev/null -w '%{url_effective}' https://github.com/SunshineStream/Sunshine/releases/latest)"
      tag="${tag##*/}"
    fi
    [ -n "$tag" ] || { E "Không xác định được phiên bản Sunshine." "Could not determine the Sunshine version."; return 1; }
    ver="${tag#v}"
    # Ưu tiên tên file thật trong danh sách release; nếu không đọc được thì dựng theo mẫu tên chuẩn
    assets="$(curl -fsSL "https://github.com/SunshineStream/Sunshine/releases/expanded_assets/$tag" 2>/dev/null)"
    debname="$(printf '%s' "$assets" | grep -oE "download/[^\"]+/sunshine_[^\"]*${flavor}_${arch}\.deb" | head -n1)"
    if [ -n "$debname" ]; then
      url="https://github.com/SunshineStream/Sunshine/releases/$debname"
    else
      url="https://github.com/SunshineStream/Sunshine/releases/download/${tag}/sunshine_${ver}-1+${flavor}_${arch}.deb"
    fi
  fi

  R "      Tải Sunshine (.deb)" "      Downloading Sunshine (.deb)" curl -fsSL -o /tmp/sunshine.deb "$url" \
    || { E "Không tải được: $url" "Could not download: $url"; return 1; }
  # apt cài kèm các thư viện phụ thuộc; nếu apt lỗi (kho apt không tới được) thì cài thẳng bằng dpkg rồi bù thư viện sau
  if ! R "      Cài Sunshine (kèm thư viện phụ thuộc, hơi lâu)" "      Installing Sunshine (with dependencies, takes a while)" \
       $SUDO $APT install -y /tmp/sunshine.deb; then
    E "apt cài Sunshine lỗi, thử dpkg trực tiếp rồi bù thư viện..." "apt failed to install Sunshine, trying dpkg directly and fixing libraries afterwards..."
    R "      dpkg -i Sunshine" "      dpkg -i Sunshine" $SUDO dpkg -i --force-depends /tmp/sunshine.deb || { rm -f /tmp/sunshine.deb; return 1; }
  fi
  rm -f /tmp/sunshine.deb
  ensure_sunshine_libs || true
}

install_moonlight() {
  local dir="$BASE/moonlight" arch url
  if [ -x "$dir/web-server" ]; then
    L "      Moonlight Web đã có." "      Moonlight Web already installed."; return 0
  fi
  case "$(uname -m)" in
    x86_64) arch="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) arch="aarch64-unknown-linux-gnu" ;;
    *) E "Moonlight Web: arch không hỗ trợ" "Moonlight Web: unsupported architecture"; return 1 ;;
  esac
  if [ -n "${MOONLIGHT_VERSION:-}" ]; then
    url="https://github.com/MrCreativ3001/moonlight-web-stream/releases/download/${MOONLIGHT_VERSION}/moonlight-web-${arch}.tar.gz"
  else
    url="https://github.com/MrCreativ3001/moonlight-web-stream/releases/latest/download/moonlight-web-${arch}.tar.gz"
  fi
  mkdir -p "$dir"
  R "      Tải Moonlight Web" "      Downloading Moonlight Web" curl -fsSL -o /tmp/moonlight-web.tar.gz "$url" || return 1
  R "      Giải nén Moonlight Web" "      Extracting Moonlight Web" tar -xzf /tmp/moonlight-web.tar.gz -C "$dir" --strip-components=1 || return 1
  rm -f /tmp/moonlight-web.tar.gz
  chmod +x "$dir/web-server"
}

# Giao diện Moonlight Web mặc định thử WebRTC (UDP) trước ("auto") nên hay báo lỗi WebRTC khi đi qua
# Cloudflare Tunnel (chỉ chuyển HTTP/WebSocket). Đổi mặc định sang "websocket" trong file JS tĩnh.
# (Trình duyệt đã lưu cài đặt cũ thì phải đổi tay trong Settings > Data Transport, hoặc xóa dữ liệu trang.)
patch_moonlight_ui() {
  local sd="$BASE/moonlight/static" want="${MOONLIGHT_TRANSPORT:-websocket}" f n=0
  [ -d "$sd" ] || return 0
  case "$want" in websocket|auto) ;; *) want=websocket ;; esac
  for f in "$sd"/*.js; do
    [ -f "$f" ] || continue
    if grep -q 'dataTransport:"auto",language:"en"\|dataTransport:"websocket",language:"en"' "$f"; then
      sed -i "s/dataTransport:\"\(auto\|websocket\)\",language:\"en\"/dataTransport:\"${want}\",language:\"en\"/g" "$f" && n=$((n+1))
    fi
  done
  [ "$n" -gt 0 ] && L "Moonlight Web: Data Transport mặc định = $want ($n file)" "Moonlight Web: default Data Transport = $want ($n files)"

  # Mặc định stream của giao diện là 1080p / 60 FPS / 10 Mbps (rất nặng với máy ít CPU): đặt lại cho nhẹ hơn.
  # Độ phân giải stream nên bằng độ phân giải màn hình ảo (RESOLUTION) để Sunshine khỏi phải co giãn ảnh.
  local rw rh fps br m=0
  if [[ "${RESOLUTION:-1366x768}" =~ ^([0-9]+)x([0-9]+)$ ]]; then rw="${BASH_REMATCH[1]}"; rh="${BASH_REMATCH[2]}"; else rw=1280; rh=720; fi
  fps="${STREAM_FPS:-60}"; br="${STREAM_BITRATE:-10000}"
  [[ "$fps" =~ ^[0-9]+$ ]] || fps=30
  [[ "$br" =~ ^[0-9]+$ ]] || br=6000
  for f in "$sd"/*.js; do
    [ -f "$f" ] || continue
    if grep -qE 'bitrate:[0-9e.]+,fps:[0-9]+,videoSize:"custom",videoSizeCustom:\{width:[0-9]+,height:[0-9]+\}' "$f"; then
      sed -i -E "s/bitrate:[0-9e.]+,fps:[0-9]+,videoSize:\"custom\",videoSizeCustom:\{width:[0-9]+,height:[0-9]+\}/bitrate:${br},fps:${fps},videoSize:\"custom\",videoSizeCustom:{width:${rw},height:${rh}}/g" "$f" && m=$((m+1))
    fi
  done
  [ "$m" -gt 0 ] && L "Moonlight Web: stream mặc định ${rw}x${rh} @ ${fps} FPS, ${br} kbps" "Moonlight Web: default stream ${rw}x${rh} @ ${fps} FPS, ${br} kbps"
  return 0
}

install_stream() {
  install_sunshine || return 1
  install_moonlight || return 1
}

# ---------------------------------------------------------------------
# Ứng dụng: Chromium (không snap) + OpenJDK 25 + PolyMC
make_app_wrappers() {
  # Chromium trong container cần --no-sandbox (không có user namespace)
  cat > "$BIN/chromium-rd" <<'EOF'
#!/bin/bash
exec chromium --no-sandbox --disable-gpu --disable-dev-shm-usage --password-store=basic "$@"
EOF
  # PolyMC (AppImage đã giải nén) + chọn sẵn Java 25
  cat > "$BIN/polymc" <<'EOF'
#!/bin/bash
for d in /opt/jdk-25 /usr/lib/jvm/java-25-openjdk-*; do
  if [ -x "$d/bin/java" ]; then export JAVA_HOME="$d"; export PATH="$d/bin:$PATH"; break; fi
done
export QT_QPA_PLATFORM=xcb
unset LIBGL_ALWAYS_SOFTWARE
# PolyMC 7.0 dùng Qt build với OpenSSL 1.1; Ubuntu 24.04 chỉ có OpenSSL 3 nên Qt báo
# "TLS initialization failed". Cho Qt thấy đúng libssl/libcrypto 1.1 đi kèm AppImage
# (chỉ 2 file này, không thêm cả thư mục lib để khỏi ảnh hưởng Java/Minecraft).
P="$HOME/.remote-desktop/polymc"
mkdir -p "$P/ssl11"
ln -sf "$P/squashfs-root/usr/lib/libssl.so.1.1" "$P/ssl11/libssl.so.1.1"
ln -sf "$P/squashfs-root/usr/lib/libcrypto.so.1.1" "$P/ssl11/libcrypto.so.1.1"
export LD_LIBRARY_PATH="$P/ssl11${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$P/squashfs-root/AppRun" "$@"
EOF
  chmod +x "$BIN/chromium-rd" "$BIN/polymc"
  $SUDO ln -sf "$BIN/chromium-rd" /usr/local/bin/chromium-rd 2>/dev/null || true
  $SUDO ln -sf "$BIN/polymc" /usr/local/bin/polymc 2>/dev/null || true
}

install_java() {
  if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q '"25'; then
    L "      Java 25 đã có." "      Java 25 already installed."; return 0
  fi
  if R "      Cài OpenJDK 25 (apt)" "      Installing OpenJDK 25 (apt)" $SUDO $APT install -y --no-install-recommends openjdk-25-jdk; then
    local j; j="$(ls -d /usr/lib/jvm/java-25-openjdk-*/ 2>/dev/null | head -n1)"
    if [ -n "$j" ]; then   # đặt Java 25 làm mặc định
      $SUDO update-alternatives --set java "${j}bin/java" >/dev/null 2>&1
      $SUDO update-alternatives --set javac "${j}bin/javac" >/dev/null 2>&1
    fi
    return 0
  fi

  E "Không cài được openjdk-25 bằng apt, thử Eclipse Temurin 25..." "openjdk-25 not available via apt, trying Eclipse Temurin 25..."
  local arch
  case "$(uname -m)" in x86_64) arch=x64 ;; aarch64|arm64) arch=aarch64 ;; *) E "Arch không hỗ trợ" "Unsupported architecture"; return 1 ;; esac
  R "      Tải Temurin JDK 25" "      Downloading Temurin JDK 25" curl -fsSL \
    "https://api.adoptium.net/v3/binary/latest/25/ga/linux/$arch/jdk/hotspot/normal/eclipse" \
    -o /tmp/jdk25.tar.gz || return 1
  $SUDO mkdir -p /opt/jdk-25
  R "      Giải nén Temurin vào /opt/jdk-25" "      Extracting Temurin to /opt/jdk-25" \
    $SUDO tar -xzf /tmp/jdk25.tar.gz -C /opt/jdk-25 --strip-components=1 || return 1
  rm -f /tmp/jdk25.tar.gz
  $SUDO ln -sf /opt/jdk-25/bin/java /usr/local/bin/java
  $SUDO ln -sf /opt/jdk-25/bin/javac /usr/local/bin/javac
}

install_chromium() {
  if command -v chromium >/dev/null 2>&1 && ! chromium --version 2>&1 | grep -qi snap; then
    L "      Chromium đã có." "      Chromium already installed."; return 0
  fi
  R "      Cài công cụ thêm PPA" "      Installing PPA tools" $SUDO $APT install -y --no-install-recommends software-properties-common gnupg || return 1
  # Ubuntu chỉ có Chromium dạng snap (không chạy được trong container) -> dùng PPA xtradeb (gói .deb)
  R "      Thêm PPA xtradeb/apps" "      Adding PPA xtradeb/apps" $SUDO env PATH=/usr/sbin:/usr/bin:/sbin:/bin add-apt-repository -y ppa:xtradeb/apps || return 1
  printf 'Package: chromium*\nPin: release o=LP-PPA-xtradeb-apps\nPin-Priority: 700\n' \
    | $SUDO tee /etc/apt/preferences.d/chromium-xtradeb >/dev/null
  R "      Cập nhật danh sách gói" "      Updating package lists" $SUDO $APT update -qq || return 1
  R "      Cài Chromium" "      Installing Chromium" $SUDO $APT install -y --no-install-recommends chromium fonts-liberation || return 1
}

install_polymc() {
  if [ "$(uname -m)" != "x86_64" ]; then E "PolyMC AppImage chỉ có cho x86_64." "The PolyMC AppImage is x86_64 only."; return 1; fi
  R "      Cài thư viện cho Qt/Minecraft" "      Installing Qt/Minecraft libraries" $SUDO $APT install -y --no-install-recommends \
    libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-render-util0 libxcb-xinerama0 libxcb-shape0 libxcb-xkb1 libxcb-randr0 \
    libxrandr2 libxcursor1 libxxf86vm1 libxi6 libxrender1 libxtst6 libopenal1 libnss3 \
    || return 1

  local dir="$BASE/polymc" ver="${POLYMC_VERSION:-7.0}"
  mkdir -p "$dir"
  if [ -x "$dir/squashfs-root/AppRun" ]; then
    L "      PolyMC đã có." "      PolyMC already installed."
  else
    R "      Tải PolyMC $ver" "      Downloading PolyMC $ver" wget -q -O "$dir/PolyMC.AppImage" \
      "https://github.com/PolyMC/PolyMC/releases/download/$ver/PolyMC-Linux-$ver-x86_64.AppImage" || return 1
    chmod +x "$dir/PolyMC.AppImage"
    # Container không có FUSE -> giải nén AppImage ra thư mục rồi chạy AppRun
    ( cd "$dir" && R "      Giải nén PolyMC" "      Extracting PolyMC" ./PolyMC.AppImage --appimage-extract ) || return 1
    rm -f "$dir/PolyMC.AppImage"
  fi
}

install_apps() {
  setup_apt_mirror || true
  install_java     || E "Java 25: lỗi (xem $INSTALL_LOG)" "Java 25: failed (see $INSTALL_LOG)"
  install_chromium || E "Chromium: lỗi (xem $INSTALL_LOG)" "Chromium: failed (see $INSTALL_LOG)"
  install_polymc   || E "PolyMC: lỗi (xem $INSTALL_LOG)" "PolyMC: failed (see $INSTALL_LOG)"
  make_app_wrappers
  L "      Xong. Mở từ menu chuột phải trên desktop, hoặc gõ: chromium-rd | polymc | gpurun polymc" \
    "      Done. Open from the desktop right-click menu, or run: chromium-rd | polymc | gpurun polymc"
}

# ---------------------------------------------------------------------
# GPU: Tesla T4 là card compute (không có cổng xuất hình), nên không chạy Xorg
# với driver NVIDIA. Thay vào đó: dùng driver kernel của host, cài thêm thư viện
# userspace (OpenGL/EGL/Vulkan/NVENC) đúng phiên bản. Sunshine nén video bằng NVENC;
# ứng dụng 3D chạy bằng EGL + VirtualGL:  gpurun <lệnh>
make_gpurun() {
  cat > "$BIN/gpurun" <<'EOF'
#!/bin/bash
# Chạy ứng dụng OpenGL bằng GPU NVIDIA (EGL headless qua VirtualGL)
unset LIBGL_ALWAYS_SOFTWARE
export DISPLAY="${DISPLAY:-:20}"
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
if command -v vglrun >/dev/null 2>&1; then
  exec vglrun -d egl "$@"
else
  exec "$@"
fi
EOF
  chmod +x "$BIN/gpurun"
  $SUDO ln -sf "$BIN/gpurun" /usr/local/bin/gpurun 2>/dev/null || true

  # nvidia-smi: tự thêm thư mục thư viện NVIDIA của host (Colab: /usr/lib64-nvidia)
  # chỉ cho riêng lệnh này, không đụng LD_LIBRARY_PATH toàn hệ thống (tránh crash Xvfb/swrast)
  cat > "$BIN/nvidia-smi" <<'EOF'
#!/bin/bash
L=""
[ -r /etc/remote-desktop-ld.path ] && read -r SAVED_LD < /etc/remote-desktop-ld.path && L=":$SAVED_LD"
for d in /usr/lib64-nvidia /usr/local/nvidia/lib64 /usr/local/nvidia/lib /usr/lib/x86_64-linux-gnu /usr/lib64; do
  [ -d "$d" ] && L="$L:$d"
done
export LD_LIBRARY_PATH="${L#:}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
[ -r /etc/remote-desktop-nvidia-smi.path ] && read -r SAVED < /etc/remote-desktop-nvidia-smi.path
for b in "${SAVED:-}" /opt/bin/nvidia-smi /usr/local/nvidia/bin/nvidia-smi /usr/bin/nvidia-smi /usr/lib64-nvidia/bin/nvidia-smi; do
  [ -x "$b" ] && exec "$b" "$@"
done
echo "nvidia-smi not found" >&2; exit 1
EOF
  chmod +x "$BIN/nvidia-smi"
}

install_gpu() {
  make_gpurun
  setup_apt_mirror || true
  local NVSMI="$BIN/nvidia-smi"
  if ! "$NVSMI" -L >/dev/null 2>&1; then
    E "Không phát hiện GPU NVIDIA (nvidia-smi không chạy được) - bỏ qua phần GPU." \
      "No NVIDIA GPU detected (nvidia-smi failed) - skipping the GPU part."
    E "Nếu dùng Colab: Runtime > Change runtime type > chọn T4 GPU." \
      "On Colab: Runtime > Change runtime type > select T4 GPU."
    return 0
  fi

  local ver name major
  ver="$("$NVSMI" --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d ' ')"
  name="$("$NVSMI" --query-gpu=name --format=csv,noheader | head -n1)"
  major="${ver%%.*}"
  L "GPU: $name | driver của host: $ver" "GPU: $name | host driver: $ver"

  R "      Cài thư viện OpenGL/EGL/Vulkan nền" "      Installing base OpenGL/EGL/Vulkan libraries" $SUDO $APT install -y --no-install-recommends \
    libglvnd0 libegl1 libgl1 libglx0 libgles2 libopengl0 \
    libvulkan1 vulkan-tools mesa-utils wget kmod

  # 1) Thư viện userspace NVIDIA khớp đúng phiên bản driver của host (không cài kernel module)
  if ldconfig -p | grep -q 'libEGL_nvidia.so.0' && ldconfig -p | grep -q 'libGLX_nvidia.so.0'; then
    L "      Đã có thư viện OpenGL/EGL của NVIDIA." "      NVIDIA OpenGL/EGL libraries already present."
  else
    local runf="/tmp/NVIDIA-Linux-x86_64-$ver.run"
    if R "      Tải thư viện NVIDIA $ver" "      Downloading NVIDIA libraries $ver" wget -q -O "$runf" \
         "https://download.nvidia.com/XFree86/Linux-x86_64/$ver/NVIDIA-Linux-x86_64-$ver.run" \
       && R "      Cài thư viện NVIDIA (bỏ qua kernel module)" "      Installing NVIDIA libraries (no kernel module)" $SUDO sh "$runf" --silent \
            --no-kernel-module --no-kernel-module-source \
            --no-nouveau-check --no-nvidia-modprobe --no-x-check --no-drm \
            --no-check-for-alternate-installs --no-install-libglvnd; then
      :
    else
      E "Cài bản .run lỗi, thử gói apt libnvidia-gl-$major (có thể lệch minor version)..." \
        "The .run installer failed, trying apt package libnvidia-gl-$major (minor version may differ)..."
      R "      Cài libnvidia-gl-$major" "      Installing libnvidia-gl-$major" $SUDO $APT install -y --no-install-recommends "libnvidia-gl-$major" \
        || R "      Cài libnvidia-gl-$major-server" "      Installing libnvidia-gl-$major-server" $SUDO $APT install -y --no-install-recommends "libnvidia-gl-$major-server" \
        || E "Không cài được thư viện GL của NVIDIA." "Could not install the NVIDIA GL libraries."
    fi
    rm -f "$runf"
    $SUDO ldconfig >/dev/null 2>&1
  fi

  # 2) Đảm bảo glvnd/Vulkan nhận ra NVIDIA
  if [ ! -e /usr/share/glvnd/egl_vendor.d/10_nvidia.json ]; then
    $SUDO mkdir -p /usr/share/glvnd/egl_vendor.d
    echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}' \
      | $SUDO tee /usr/share/glvnd/egl_vendor.d/10_nvidia.json >/dev/null
  fi
  if [ ! -e /usr/share/vulkan/icd.d/nvidia_icd.json ] && [ ! -e /etc/vulkan/icd.d/nvidia_icd.json ]; then
    $SUDO mkdir -p /usr/share/vulkan/icd.d
    echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3"}}' \
      | $SUDO tee /usr/share/vulkan/icd.d/nvidia_icd.json >/dev/null
  fi

  # 3) VirtualGL (đẩy hình từ GPU sang màn hình ảo Xvfb)
  if ! command -v vglrun >/dev/null 2>&1 && [ "$(uname -m)" = "x86_64" ]; then
    local v="${VGL_VERSION:-3.1.1}" deb="/tmp/virtualgl.deb"
    if R "      Tải VirtualGL $v" "      Downloading VirtualGL $v" wget -q -O "$deb" \
         "https://github.com/VirtualGL/virtualgl/releases/download/$v/virtualgl_${v}_amd64.deb" \
       && R "      Cài VirtualGL" "      Installing VirtualGL" $SUDO $APT install -y "$deb"; then
      :
    else
      E "Không cài được VirtualGL (gpurun sẽ chạy app trực tiếp, không qua vglrun)." \
        "Could not install VirtualGL (gpurun will run apps directly, without vglrun)."
    fi
    rm -f "$deb"
  fi

  make_gpurun
  L "      GPU xong. Kiểm tra sau khi start: $0 gpu" "      GPU done. Check after start: $0 gpu"
}

gpu_check() {
  echo "=== nvidia-smi ==="
  "$BIN/nvidia-smi" 2>&1 | head -n 15
  echo
  echo "=== $(t "Thư viện NVIDIA" "NVIDIA libraries") ==="
  ldconfig -p | grep -E 'libEGL_nvidia|libGLX_nvidia|libcuda\.so|libnvidia-encode' || echo "$(t "(không thấy)" "(none found)")"
  echo
  echo "=== $(t "Encoder của Sunshine (cần đã chạy start)" "Sunshine encoder (needs start to have run)") ==="
  grep -E 'Found .*encoder|Encoder \[.*\] (failed|succeeded)|Trying encoder' "$LOG/sunshine.log" 2>/dev/null | tail -n 6 | cut -c1-160 \
    || true
  [ -s "$LOG/sunshine.log" ] || echo "$(t "(chưa có log Sunshine)" "(no Sunshine log yet)")"
  echo
  echo "=== $(t "Thiết bị nhập liệu" "Input device") ==="
  if [ -e /dev/uinput ]; then echo "/dev/uinput: OK"; else
    echo "$(t "/dev/uinput: KHÔNG CÓ (tay cầm sẽ tắt; chuột/bàn phím có thể vẫn chạy qua X11)" \
               "/dev/uinput: MISSING (gamepads disabled; mouse/keyboard may still work through X11)")"
  fi
  echo
  echo "=== $(t "OpenGL qua gpurun (cần desktop đang chạy)" "OpenGL via gpurun (desktop must be running)") ==="
  if command -v glxinfo >/dev/null; then
    DISPLAY=":${DISP_NUM}" "$BIN/gpurun" glxinfo -B 2>&1 | grep -E 'OpenGL (vendor|renderer|version)' \
      || echo "$(t "Không đọc được. Hãy chạy '$0 start' trước." "Cannot read it. Run '$0 start' first.")"
  else
    echo "$(t "Chưa có glxinfo (cài mesa-utils)." "glxinfo missing (install mesa-utils).")"
  fi
}

# ---------------------------------------------------------------------
# Cấu hình desktop Openbox + lxpanel (menu/panel tiếng Anh)
write_desktop_config() {
  local ob="$HOME/.config/openbox"
  mkdir -p "$ob"

  # Menu chuột phải (tự sinh lại mỗi lần start; muốn tự chỉnh tay thì xóa dòng "colabgaming" trong file)
  if [ ! -f "$ob/menu.xml" ] || grep -q 'colabgaming' "$ob/menu.xml"; then
    mi() { printf '  <item label="%s"><action name="Execute"><command>%s</command></action></item>\n' "$1" "$2"; }
    {
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      echo '<!-- colabgaming: auto-generated on every start; delete this line to edit by hand -->'
      echo '<openbox_menu xmlns="http://openbox.org/3.4/menu">'
      echo '<menu id="root-menu" label="Openbox">'
      mi "Terminal" "lxterminal"
      mi "File manager" "pcmanfm"
      mi "Task manager" "lxtask"
      mi "Chromium" "chromium-rd"
      mi "PolyMC" "polymc"
      mi "PolyMC (GPU)" "gpurun polymc"
      mi "GPU info (nvidia-smi)" "xterm -hold -e nvidia-smi"
      echo '  <separator/>'
      echo '  <item label="Reconfigure"><action name="Reconfigure"/></item>'
      echo '  <item label="Restart Openbox"><action name="Restart"/></item>'
      echo '  <item label="Exit"><action name="Exit"><prompt>no</prompt></action></item>'
      echo '</menu>'
      echo '</openbox_menu>'
    } > "$ob/menu.xml"
  fi

  # Autostart: bật thanh panel LXDE
  if [ ! -f "$ob/autostart" ] || grep -q 'colabgaming' "$ob/autostart"; then
    {
      echo '# colabgaming: auto-generated on every start; delete this line to edit by hand'
      echo '(sleep 1; lxpanel) &'
    } > "$ob/autostart"
  fi

  # Icon theme cho GTK (nếu không có sẽ hiện icon "thay thế" hình thoi xanh)
  if [ ! -f "$HOME/.gtkrc-2.0" ]; then
    printf 'gtk-icon-theme-name="nuoveXT2"\ngtk-font-name="Sans 10"\n' > "$HOME/.gtkrc-2.0"
  fi
  mkdir -p "$HOME/.config/gtk-3.0"
  if [ ! -f "$HOME/.config/gtk-3.0/settings.ini" ]; then
    printf '[Settings]\ngtk-icon-theme-name=nuoveXT2\ngtk-font-name=Sans 10\n' > "$HOME/.config/gtk-3.0/settings.ini"
  fi

  # Cấu hình thanh panel LXDE (chỉ tạo nếu chưa có; thiếu file này lxpanel chỉ dựng panel nhỏ xíu).
  # Xóa ~/.config/lxpanel/default/panels/panel để tạo lại mặc định.
  local pd="$HOME/.config/lxpanel/default/panels"
  mkdir -p "$pd"
  if [ ! -f "$pd/panel" ]; then
    cat > "$pd/panel" <<'EOF'
Global {
    edge=bottom
    allign=left
    margin=0
    widthtype=percent
    width=100
    height=34
    transparent=0
    tintcolor=#000000
    alpha=0
    setdocktype=1
    setpartialstrut=1
    autohide=0
    heightwhenhidden=2
    usefontcolor=0
    background=0
    iconsize=26
}
Plugin {
    type=menu
    Config {
        image=/usr/share/lxpanel/images/my-computer.png
        system {
        }
        separator {
        }
        item {
            command=run
        }
    }
}
Plugin {
    type=launchbar
    Config {
        Button {
            id=pcmanfm.desktop
        }
        Button {
            id=lxterminal.desktop
        }
    }
}
Plugin {
    type=space
    Config {
        Size=4
    }
}
Plugin {
    type=taskbar
    expand=1
    Config {
        tooltips=1
        IconsOnly=0
        ShowAllDesks=0
        UseMouseWheel=1
        UseUrgencyHint=1
        FlatButton=0
        MaxTaskWidth=180
        spacing=1
    }
}
Plugin {
    type=tray
}
Plugin {
    type=dclock
    Config {
        ClockFmt=%H:%M
        TooltipFmt=%A %x
        BoldFont=0
        IconOnly=0
        CenterText=0
    }
}
EOF
  fi
}

# Cấu hình Sunshine + tài khoản web UI
write_sunshine_config() {
  local d="$HOME/.config/sunshine"
  mkdir -p "$d"
  # Chỉ ghi đè khi file do script tạo (có dòng "colabgaming")
  if [ ! -f "$d/sunshine.conf" ] || grep -q 'colabgaming' "$d/sunshine.conf"; then
    {
      cat <<'EOF'
# colabgaming: auto-generated on every start; delete this line to edit by hand
sunshine_name = Colabgaming
capture = x11
address_family = ipv4
origin_web_ui_allowed = pc
system_tray = disabled
sw_preset = ultrafast
sw_tune = zerolatency
EOF
      if [ "${SUNSHINE_CODECS:-h264}" != "all" ]; then
        # Chỉ quảng cáo H.264: nếu quảng cáo cả H.265/AV1, trình duyệt có thể chọn chúng rồi báo
        # "VideoDecoder has an error EncodingError: Decoding error" (hay gặp khi GPU nén được HEVC bằng NVENC)
        echo 'hevc_mode = 1'
        echo 'av1_mode = 1'
      fi
    } > "$d/sunshine.conf"
  fi
  printf '%s:%s\n' "$SUN_USER" "$SUN_PASS" > "$BASE/sunshine.cred"; chmod 600 "$BASE/sunshine.cred"
  : > "$LOG/sunshine-creds.log"
  "$SUN_BIN" --creds "$SUN_USER" "$SUN_PASS" >> "$LOG/sunshine-creds.log" 2>&1 \
    || {
      E "Không đặt được tài khoản Sunshine (xem $LOG/sunshine-creds.log)" "Could not set the Sunshine account (see $LOG/sunshine-creds.log)"
      tail -n 8 "$LOG/sunshine-creds.log" 2>/dev/null | cut -c1-170
      ldd "$SUN_BIN" 2>/dev/null | grep 'not found' \
        && E "Sunshine thiếu thư viện ở trên. Chạy lại: $0 install-stream" "Sunshine is missing the libraries above. Run again: $0 install-stream"
    }
}

# Chuẩn bị cấu hình + script khởi động (nhẹ, không compositor)
prepare_config() {
  make_gpurun
  make_app_wrappers
  write_desktop_config
  write_sunshine_config

  # Wrapper chạy Xvfb + PulseAudio + Sunshine, tự giám sát:
  #  - tự chạy Xvfb (để biết chính xác nó thoát vì lý do gì: mã 139 = segfault, 137 = bị kill...)
  #  - Xvfb chết/treo hoặc Sunshine thoát => ghi sự kiện vào xvfb-events.log, dọn sạch, để vòng lặp chạy lại
  cat > "$BIN/stream-run" <<'EOF'
#!/bin/bash
# stream-run <màn hình> <WxH> <lệnh chạy Sunshine...>      (RD_LOG = thư mục log)
D="$1"; RES="$2"; shift 2
L="${RD_LOG:-/tmp}"
SOCK="/tmp/.X11-unix/X$D"
EV="$L/xvfb-events.log"
export DISPLAY=":$D"
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

alive() {  # tiến trình còn sống và không phải zombie
  local st; st="$(awk '/^State:/{print $2}' "/proc/$1/status" 2>/dev/null)"
  [ -n "$st" ] && [ "$st" != "Z" ]
}
cleanup_x() {
  pkill -f "Xvfb :$D " 2>/dev/null
  pkill -x pulseaudio 2>/dev/null
  rm -f "/tmp/.X$D-lock" "$SOCK"
}
cleanup_x   # bắt đầu từ trạng thái sạch

# Xvfb chỉ được thấy EGL của Mesa (EGL của NVIDIA làm swrast crash khi khởi tạo GLX)
if [ -e /usr/share/glvnd/egl_vendor.d/50_mesa.json ]; then
  EGLENV="__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json"
else
  EGLENV="__EGL_VENDOR_LIBRARY_DIRS=/nonexistent"
fi
env -u LD_LIBRARY_PATH "$EGLENV" Xvfb ":$D" -screen 0 "${RES}x24" -s 0 -dpms +extension COMPOSITE +extension DAMAGE \
  +extension GLX +extension RANDR +extension RENDER +extension MIT-SHM +extension XFIXES \
  +extension XTEST +iglx +render -nolisten tcp -ac -noreset -shmem >> "$L/xvfb.log" 2>&1 &
xpid=$!
for i in $(seq 1 60); do
  [ -S "$SOCK" ] && break
  alive "$xpid" || break
  sleep 0.5
done
if [ ! -S "$SOCK" ]; then
  echo "[$(date '+%F %T')] Xvfb failed to start (see $L/xvfb.log)" | tee -a "$EV"
  cleanup_x; exit 1
fi

# Âm thanh (Sunshine cần PulseAudio); không có cũng vẫn stream được hình
if command -v pulseaudio >/dev/null 2>&1; then
  pulseaudio -D --exit-idle-time=-1 --log-target="file:$L/pulseaudio.log" >/dev/null 2>&1 || true
fi

"$@" &
spid=$!
trap 'kill "$spid" "$xpid" 2>/dev/null' TERM INT

why=""; up=0; fails=0; tick=0
while :; do
  sleep 1
  tick=$((tick+1))
  if ! alive "$xpid"; then
    wait "$xpid" 2>/dev/null; code=$?
    why="Xvfb exited, code $code (134=X server abort, 139=segfault, 137=SIGKILL/OOM, 135=SIGBUS)"
    break
  fi
  if ! alive "$spid"; then
    wait "$spid" 2>/dev/null; code=$?
    why="Sunshine exited, code $code"
    break
  fi
  [ $((tick % 5)) -eq 0 ] || continue      # kiểm tra phản hồi X mỗi 5 giây (rẻ hơn nhiều so với mỗi giây)
  if DISPLAY=":$D" timeout 5 xset q >/dev/null 2>&1; then
    up=1; fails=0
  elif [ "$up" = 1 ]; then
    fails=$((fails+1))
    if [ "$fails" -ge 20 ]; then why="Xvfb hung, no reply for ~100s"; break; fi
  fi
done

{
  echo "=== [$(date '+%F %T')] $why"
  free -m | head -2
  df -h /dev/shm | tail -n 1
  ps aux --sort=-%mem | head -5 | cut -c1-140
} >> "$EV"
echo "[stream-run] $why"

kill "$spid" 2>/dev/null; sleep 2; kill -9 "$spid" 2>/dev/null
cleanup_x
exit 1
EOF
  chmod +x "$BIN/stream-run"

  # Script khởi động session (chạy trên màn hình :20)
  cat > "$BASE/xstartup" <<'EOF'
#!/bin/bash
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XDG_SESSION_TYPE=x11 GDK_BACKEND=x11
export XDG_CURRENT_DESKTOP=LXDE XDG_MENU_PREFIX=lxde-
export NO_AT_BRIDGE=1 GTK_OVERLAY_SCROLLING=0
export PATH="$HOME/.remote-desktop/bin:$PATH"
xset s off -dpms s noblank 2>/dev/null
xsetroot -solid "#2e3440" 2>/dev/null
exec dbus-launch --exit-with-session openbox-session
EOF
  chmod +x "$BASE/xstartup"
}

# ---------------------------------------------------------------------
# Thay thế systemd: vòng lặp tự restart service khi chết
# svc_start <name> <command...>
svc_start() {
  local name="$1"; shift
  local pidf="$RUN/$name.pid"
  if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then
    L "$name đã chạy (pid $(cat "$pidf"))" "$name already running (pid $(cat "$pidf"))"; return
  fi
  local cmd; cmd="$(printf '%q ' "$@")"
  setsid nohup bash -c "
    while true; do
      $cmd >> '$LOG/$name.log' 2>&1
      echo \"[\$(date '+%F %T')] $name exited, restarting in 2s\" >> '$LOG/$name.log'
      sleep 2
    done" >/dev/null 2>&1 &
  echo $! > "$pidf"
  L "Đã chạy $name (pid $!)" "Started $name (pid $!)"
}

svc_stop() {
  local name="$1" pidf="$RUN/$1.pid"
  if [ -f "$pidf" ]; then
    local p; p="$(cat "$pidf")"
    kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null
    rm -f "$pidf"
  fi
}

# ---------------------------------------------------------------------
# Phát hiện bộ dịch vụ của user KHÁC đang chạy (cùng màn hình :20 và cùng cổng 47989/6080 sẽ xung đột)
check_conflict() {
  local me others u
  me="$(id -un)"
  others="$(ps -eo user:32=,args= 2>/dev/null \
    | grep -E "[s]tream-run|[X]vfb :${DISP_NUM} |[w]eb-server|[s]unshine( |$)|[c]loudflared tunnel" \
    | awk '{print $1}' | sort -u | grep -vx "$me" | tr '\n' ' ')"
  [ -n "${others// /}" ] || return 0
  E "Đang có dịch vụ của user khác chạy: $others- sẽ xung đột (cùng màn hình :${DISP_NUM}, cổng 47989 và ${WEB_PORT})." \
    "Services of another user are already running: $others- they will conflict (same display :${DISP_NUM}, ports 47989 and ${WEB_PORT})."
  for u in $others; do
    if [ "$u" = "root" ]; then
      echo "  root: pkill -x sunshine; pkill -x Xvfb; pkill -x web-server"
    else
      echo "  $(t "Dừng bằng root" "Stop as root"): RD_USER=$u ./Colabgaming.sh stop     (hoặc/or: pkill -u $u)"
    fi
  done
  E "Chỉ nên dùng MỘT user duy nhất (hiện đang chạy với: $me). Dừng các user khác rồi chạy lại start." \
    "Use ONE user only (currently running as: $me). Stop the other users, then run start again."
  return 1
}

# ---------------------------------------------------------------------
# Tự thiết lập Moonlight Web: tạo tài khoản admin, thêm PC "127.0.0.1" (KHÔNG dùng "localhost": thư viện
# stream có thể phân giải thành IPv6 ::1 trong khi Sunshine chỉ nghe IPv4 -> "Connection refused"),
# rồi tự ghép cặp (PIN do Moonlight Web sinh ra được gửi thẳng vào Sunshine).
moonlight_setup() {
  command -v python3 >/dev/null 2>&1 || { E "Không có python3, bỏ qua tự thiết lập." "python3 not found, skipping auto-setup."; return 1; }
  L "Tự thiết lập Moonlight Web (tài khoản + ghép cặp PC 127.0.0.1)..." "Auto-configuring Moonlight Web (account + pairing PC 127.0.0.1)..."

  cat > "$BIN/moonlight-setup.py" <<'PYEOF'
import sys, json, time, ssl, base64, threading
import urllib.request, urllib.parse, urllib.error, http.cookiejar

port, mu, mp, su, sp = sys.argv[1:6]
BASE = "http://127.0.0.1:%s/api" % port
SUN = "https://127.0.0.1:47990/api/pin"
cj = http.cookiejar.CookieJar()
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
ctx = ssl._create_unverified_context()


def call(method, path, body=None, query=None, timeout=30):
    url = BASE + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if data is not None else {}
    return op.open(urllib.request.Request(url, data=data, method=method, headers=headers), timeout=timeout)


def sun(method, body=None):
    data = json.dumps(body).encode() if body is not None else None
    h = {"Authorization": "Basic " + base64.b64encode(("%s:%s" % (su, sp)).encode()).decode()}
    if data is not None:
        h["Content-Type"] = "application/json"
    r = urllib.request.urlopen(urllib.request.Request(SUN, data=data, method=method, headers=h), timeout=15, context=ctx)
    return json.loads(r.read().decode() or "{}")


def done(code, msg=""):
    print("RESULT:%s:%s" % (code, msg))
    sys.exit(0)


# 1) đăng nhập (lần đầu tiên sẽ tạo tài khoản admin)
ok = False
for _ in range(40):
    try:
        call("POST", "/login", {"name": mu, "password": mp}).read()
        ok = True
        break
    except urllib.error.HTTPError as e:
        if e.code in (401, 403, 404):
            done("login_failed")
        time.sleep(1)
    except Exception:
        time.sleep(1)
if not ok:
    done("unreachable")


def list_hosts():
    r = call("GET", "/hosts")
    first = r.readline().decode().strip()
    r.close()
    try:
        return json.loads(first).get("hosts", [])
    except Exception:
        return []


def host_info(hid):
    return json.loads(call("GET", "/host", query={"host_id": hid}).read().decode()).get("host", {})


# 2) tìm PC 127.0.0.1; xóa PC "localhost" cũ (dễ gây lỗi Connection refused)
target = None
for h in list_hosts():
    try:
        info = host_info(h["host_id"])
    except Exception:
        continue
    addr = info.get("address", "")
    if addr == "127.0.0.1":
        target = info
    elif addr in ("localhost", "::1"):
        try:
            call("DELETE", "/host", query={"host_id": h["host_id"]}).read()
        except Exception:
            pass

# 3) thêm PC nếu chưa có
if target is None:
    try:
        target = json.loads(call("POST", "/host", {"address": "127.0.0.1", "http_port": None}).read().decode()).get("host")
    except Exception as e:
        done("host_failed", str(e))
if not target:
    done("host_failed", "no host returned")
if target.get("paired") == "Paired":
    done("ok", "already_paired")

# 4) ghép cặp: Moonlight Web trả về PIN, ta nhập PIN vào Sunshine qua API
result = {}


def reader():
    try:
        r = call("POST", "/pair", {"host_id": target["host_id"]}, timeout=120)
        for raw in r:
            line = raw.decode().strip()
            if not line:
                continue
            obj = json.loads(line)
            if "Pin" in obj:
                result["pin"] = obj["Pin"]
            elif "Paired" in obj:
                result["paired"] = True
                return
            else:
                result["other"] = line[:160]
    except Exception as e:
        result["err"] = str(e)


th = threading.Thread(target=reader, daemon=True)
th.start()
t0 = time.time()
while "pin" not in result and "err" not in result and time.time() - t0 < 30:
    time.sleep(0.3)
if "pin" not in result:
    done("pair_failed", result.get("err", result.get("other", "no PIN")))

pid = None
for _ in range(40):
    try:
        lst = sun("GET").get("pairings", [])
        if lst:
            pid = lst[0].get("id")
            break
    except Exception:
        pass
    time.sleep(0.5)
if not pid:
    done("pair_failed", "Sunshine has no pending pairing")
res = sun("POST", {"pairing_id": pid, "pin": result["pin"], "name": "moonlight-web"})
th.join(timeout=30)
if result.get("paired"):
    done("ok", "paired")
done("pair_failed", str(result.get("err", res)))
PYEOF

  local out code detail
  rm -f "$BASE/setup.ok"
  out="$(python3 "$BIN/moonlight-setup.py" "$WEB_PORT" "$MOON_USER" "$MOON_PASS" "$SUN_USER" "$SUN_PASS" 2>&1)"
  code="$(printf '%s\n' "$out" | grep '^RESULT:' | tail -n1 | cut -d: -f2)"
  detail="$(printf '%s\n' "$out" | grep '^RESULT:' | tail -n1 | cut -d: -f3-)"
  case "$code" in
    ok)
      printf '%s:%s\n' "$MOON_USER" "$MOON_PASS" > "$BASE/moonlight.cred"; chmod 600 "$BASE/moonlight.cred"
      : > "$BASE/setup.ok"
      L "Moonlight Web đã sẵn sàng: tài khoản '$MOON_USER', PC 127.0.0.1 đã ghép cặp." \
        "Moonlight Web is ready: account '$MOON_USER', PC 127.0.0.1 is paired."
      return 0 ;;
    login_failed)
      E "Moonlight Web đã có tài khoản khác (mật khẩu không khớp '$MOON_USER'). Đăng nhập bằng tài khoản của bạn rồi làm tay (xem hướng dẫn bên dưới), hoặc đặt MOONLIGHT_USER/MOONLIGHT_PASSWORD đúng." \
        "Moonlight Web already has a different account (password does not match '$MOON_USER'). Sign in with your own account and follow the manual steps below, or set MOONLIGHT_USER/MOONLIGHT_PASSWORD correctly." ;;
    unreachable)
      E "Không kết nối được Moonlight Web ở cổng $WEB_PORT (xem: $0 logs moonlight)." "Cannot reach Moonlight Web on port $WEB_PORT (see: $0 logs moonlight)." ;;
    host_failed)
      E "Không thêm được PC 127.0.0.1: $detail" "Could not add PC 127.0.0.1: $detail" ;;
    pair_failed)
      E "Ghép cặp tự động thất bại: $detail" "Automatic pairing failed: $detail" ;;
    *)
      E "Tự thiết lập lỗi không rõ:" "Auto-setup failed for an unknown reason:"; printf '%s\n' "$out" | tail -n 6 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------
# Chờ Sunshine mở cổng ghép cặp (47989); nếu không thì in luôn lý do để khỏi phải dò tay
check_sunshine() {
  local n="${SUNSHINE_WAIT:-45}" i
  L "Kiểm tra Sunshine đã sẵn sàng (tối đa ${n}s)..." "Checking that Sunshine is ready (up to ${n}s)..."
  for i in $(seq 1 "$n"); do
    if curl -s -m 2 -o /dev/null "http://127.0.0.1:47989/serverinfo"; then
      L "Sunshine đã sẵn sàng." "Sunshine is ready."; return 0
    fi
    sleep 1
  done
  E "Sunshine KHÔNG trả lời ở cổng 47989 - Moonlight Web sẽ báo 'Host is not reachable'." \
    "Sunshine is NOT answering on port 47989 - Moonlight Web will say 'Host is not reachable'."
  echo "--- sunshine-creds.log ---"; tail -n 8 "$LOG/sunshine-creds.log" 2>/dev/null | cut -c1-170
  echo "--- sunshine.log ---";       tail -n 15 "$LOG/sunshine.log" 2>/dev/null | cut -c1-170
  echo "--- xvfb-events ---";        tail -n 6 "$LOG/xvfb-events.log" 2>/dev/null | cut -c1-150
  echo "--- $(t "thư viện thiếu" "missing libraries") ---"; ldd "$SUN_BIN" 2>/dev/null | grep 'not found' || echo "$(t "(không)" "(none)")"
  return 1
}

start_all() {
  [ -x "$SUN_BIN" ] || { E "Chưa cài Sunshine. Chạy: $0 install" "Sunshine is not installed. Run: $0 install"; exit 1; }
  [ -x "$BASE/moonlight/web-server" ] || { E "Chưa cài Moonlight Web. Chạy: $0 install" "Moonlight Web is not installed. Run: $0 install"; exit 1; }
  command -v Xvfb >/dev/null || { E "Chưa cài Xvfb. Chạy: $0 install" "Xvfb is not installed. Run: $0 install"; exit 1; }
  command -v openbox >/dev/null && command -v lxpanel >/dev/null \
    || { E "Chưa cài Openbox/lxpanel. Chạy: $0 install" "Openbox/lxpanel are not installed. Run: $0 install"; exit 1; }
  command -v cloudflared >/dev/null || { E "Chưa cài cloudflared. Chạy: $0 install" "cloudflared is not installed. Run: $0 install"; exit 1; }
  check_conflict || exit 1
  ensure_sunshine_libs || { E "Không start được vì Sunshine thiếu thư viện (xem ở trên)." "Cannot start: Sunshine is missing libraries (see above)."; exit 1; }
  prepare_config

  # Thư mục socket X phải cho phép mọi user tạo file; dọn lock cũ (kể cả của root)
  $SUDO mkdir -p /tmp/.X11-unix && $SUDO chmod 1777 /tmp/.X11-unix
  $SUDO rm -f "/tmp/.X${DISP_NUM}-lock" "/tmp/.X11-unix/X${DISP_NUM}"

  # 1) Xvfb + PulseAudio + Sunshine (dưới wrapper tự giám sát)
  svc_start sunshine env "RD_LOG=$LOG" "$BIN/stream-run" "$DISP_NUM" "$RESOLUTION" "$SUN_BIN"

  # 2) Moonlight Web (chỉ lắng nghe localhost; Cloudflare Tunnel trỏ vào đây)
  patch_moonlight_ui
  if [ -n "${TURN_URL:-}" ]; then   # tùy chọn: TURN server cho WebRTC (WEBRTC_ICE_SERVER_n_* của Moonlight Web)
    export WEBRTC_ICE_SERVER_0_URL="$TURN_URL" WEBRTC_ICE_SERVER_0_USERNAME="${TURN_USERNAME:-}" WEBRTC_ICE_SERVER_0_CREDENTIAL="${TURN_CREDENTIAL:-}"
    L "Moonlight Web: dùng TURN server $TURN_URL" "Moonlight Web: using TURN server $TURN_URL"
  fi
  svc_start moonlight bash -c "cd '$BASE/moonlight' && BIND_ADDRESS='127.0.0.1:${WEB_PORT}' exec ./web-server"
  unset WEBRTC_ICE_SERVER_0_URL WEBRTC_ICE_SERVER_0_USERNAME WEBRTC_ICE_SERVER_0_CREDENTIAL

  # 3) Desktop session Openbox + lxpanel (chờ Xvfb sẵn sàng rồi mới chạy)
  svc_start desktop bash -c "
    for i in \$(seq 1 90); do [ -S /tmp/.X11-unix/X${DISP_NUM} ] && break; sleep 1; done
    export DISPLAY=:${DISP_NUM}
    '$BASE/xstartup'
    # xstartup thoát => chờ để vòng lặp restart
  "

  # 4) Cloudflare tunnel
  if [ -n "$CF_TOKEN" ]; then
    svc_start cloudflared cloudflared tunnel --no-autoupdate --protocol "$CF_PROTOCOL" run --token "$CF_TOKEN"
    L "Dùng named tunnel: trỏ Public Hostname tới http://localhost:${WEB_PORT} trong Cloudflare Zero Trust." \
      "Named tunnel: point the Public Hostname to http://localhost:${WEB_PORT} in Cloudflare Zero Trust."
  else
    : > "$LOG/cloudflared.log"
    svc_start cloudflared cloudflared tunnel --no-autoupdate --protocol "$CF_PROTOCOL" --url "http://localhost:${WEB_PORT}"
    L "Đợi URL từ Cloudflare..." "Waiting for the URL from Cloudflare..."
    for i in $(seq 1 30); do
      grep -qo 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG/cloudflared.log" && break; sleep 1
    done
  fi
  if check_sunshine; then moonlight_setup || true; fi
  show_url
}

stop_all() {
  for s in cloudflared desktop moonlight sunshine; do svc_stop "$s"; done
  pkill -x web-server 2>/dev/null
  pkill -x sunshine 2>/dev/null
  pkill -f "Xvfb :${DISP_NUM} " 2>/dev/null
  pkill -x pulseaudio 2>/dev/null
  pkill -x lxpanel 2>/dev/null
  pkill -x openbox 2>/dev/null
  pkill -f "cloudflared tunnel" 2>/dev/null
  $SUDO rm -f "/tmp/.X${DISP_NUM}-lock" "/tmp/.X11-unix/X${DISP_NUM}"
  L "Đã dừng tất cả." "Everything stopped."
}

show_url() {
  local u
  u="$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG/cloudflared.log" 2>/dev/null | tail -1)"
  echo "------------------------------------------------------------"
  if [ -n "$u" ]; then
    echo "URL : $u"
  elif [ -n "$CF_TOKEN" ]; then
    echo "URL : https://$(t "<hostname-của-bạn>" "<your-hostname>")"
  else
    echo "URL : $(t "(chưa có - xem: $0 logs cloudflared)" "(not ready - see: $0 logs cloudflared)")"
  fi
  echo "------------------------------------------------------------"
  local auto=0; [ -f "$BASE/setup.ok" ] && auto=1
  if [ "$RD_LANG" = "vi" ]; then
    if [ "$auto" = 1 ]; then
      cat <<EOF
Cách dùng:
 1) Mở URL và đăng nhập Moonlight Web:  $MOON_USER / $MOON_PASS
    (tài khoản và PC 127.0.0.1 đã được tự tạo và ghép cặp)
 2) Bấm vào PC "Colabgaming" -> Launch -> Desktop để xem màn hình.
 3) Data Transport đã đặt sẵn = Web Socket (Cloudflare Tunnel không chuyển UDP của WebRTC).
    Nếu vẫn thấy lỗi WebRTC: Settings > Data Transport > Web Socket, rồi Ctrl+F5 để xóa cache trang.
 4) URL công khai: hãy đổi mật khẩu mặc định bằng MOONLIGHT_PASSWORD / SUNSHINE_PASSWORD.
Tài khoản web UI Sunshine (chỉ truy cập được trong máy): $SUN_USER / $SUN_PASS
EOF
    else
      cat <<EOF
Chưa tự thiết lập xong Moonlight Web (xem thông báo phía trên). Làm tay:
 1) Mở URL, tạo tài khoản đầu tiên (người đầu tiên sẽ là admin - hãy làm ngay).
 2) Thêm PC (nút +): địa chỉ 127.0.0.1 (KHÔNG dùng 'localhost'), để trống cổng.
    Nếu đã có PC tên 'localhost' thì xóa nó đi.
 3) Bấm vào PC để Pair -> trang hiện mã PIN -> chạy:  $0 pin <PIN>     (hoặc thử lại tự động:  $0 setup)
 4) Data Transport đã đặt sẵn = Web Socket. Nếu vẫn lỗi WebRTC: Settings > Data Transport > Web Socket, rồi Ctrl+F5.
 5) Bấm Launch / Desktop để xem màn hình.
Tài khoản web UI Sunshine (chỉ truy cập được trong máy): $SUN_USER / $SUN_PASS
EOF
    fi
  else
    if [ "$auto" = 1 ]; then
      cat <<EOF
How to use:
 1) Open the URL and sign in to Moonlight Web:  $MOON_USER / $MOON_PASS
    (the account and the PC 127.0.0.1 were created and paired automatically)
 2) Click the PC "Colabgaming" -> Launch -> Desktop to see the screen.
 3) Data Transport is already preset to Web Socket (a Cloudflare Tunnel does not carry WebRTC's UDP).
    If you still see a WebRTC error: Settings > Data Transport > Web Socket, then Ctrl+F5 to clear the page cache.
 4) The URL is public: change the default passwords with MOONLIGHT_PASSWORD / SUNSHINE_PASSWORD.
Sunshine web UI account (reachable inside the machine only): $SUN_USER / $SUN_PASS
EOF
    else
      cat <<EOF
Moonlight Web auto-setup did not finish (see the message above). Do it by hand:
 1) Open the URL and create the first account (the first user becomes admin - do it right away).
 2) Add a PC (+ button): address 127.0.0.1 (do NOT use 'localhost'), leave the port empty.
    If a PC named 'localhost' already exists, delete it.
 3) Click the PC to Pair -> the page shows a PIN -> run:  $0 pin <PIN>     (or retry automatically:  $0 setup)
 4) Data Transport is already preset to Web Socket. If you still see a WebRTC error: Settings > Data Transport > Web Socket, then Ctrl+F5.
 5) Click Launch / Desktop to see the screen.
Sunshine web UI account (reachable inside the machine only): $SUN_USER / $SUN_PASS
EOF
    fi
  fi
}

status() {
  for s in sunshine moonlight desktop cloudflared; do
    if [ -f "$RUN/$s.pid" ] && kill -0 "$(cat "$RUN/$s.pid")" 2>/dev/null; then
      printf '%-12s \033[32mRUNNING\033[0m\n' "$s"
    else
      printf '%-12s \033[31mSTOPPED\033[0m\n' "$s"
    fi
  done
  show_url
}

# Nhập mã PIN ghép cặp vào Sunshine (thay cho việc mở web UI của Sunshine)
pin_cmd() {
  local pin="${1:-}" pid="${2:-}" api="https://127.0.0.1:47990/api/pin" list res
  if ! [[ "$pin" =~ ^[0-9]{4}$ ]]; then
    E "Cách dùng: $0 pin <PIN 4 số hiện trên Moonlight Web>" "Usage: $0 pin <4-digit PIN shown by Moonlight Web>"
    exit 1
  fi
  list="$(curl -sk -m 10 -u "$SUN_USER:$SUN_PASS" "$api")" \
    || { E "Không kết nối được Sunshine (đã chạy start chưa?)" "Cannot reach Sunshine (did you run start?)"; exit 1; }
  if [ -z "$pid" ]; then
    pid="$(printf '%s' "$list" | grep -oE '"id" *: *"[0-9a-fA-F]{32}"' | head -n1 | grep -oE '[0-9a-fA-F]{32}')"
  fi
  if [ -z "$pid" ]; then
    E "Chưa có yêu cầu ghép cặp nào đang chờ. Bấm Pair trên Moonlight Web trước, rồi chạy lại lệnh này." \
      "No pairing request is pending. Click Pair in Moonlight Web first, then run this again."
    echo "Sunshine: $list" | cut -c1-200
    exit 1
  fi
  res="$(curl -sk -m 10 -u "$SUN_USER:$SUN_PASS" -H 'Content-Type: application/json' \
        -d "{\"pairing_id\":\"$pid\",\"pin\":\"$pin\",\"name\":\"moonlight-web\"}" "$api")"
  if printf '%s' "$res" | grep -qE '"status" *: *true'; then
    L "Ghép cặp thành công." "Pairing succeeded."
  else
    E "Ghép cặp thất bại: $res" "Pairing failed: $res"
    exit 1
  fi
}

case "${1:-}" in
  user)           ensure_user && L "Xong. Chuyển user thủ công bằng: su - $RD_USER" "Done. Switch user manually with: su - $RD_USER" ;;
  install)        install_all ;;
  install-stream) install_stream ;;
  install-gpu)    install_gpu ;;
  install-apps)   install_apps ;;
  start)          start_all ;;
  stop)           stop_all ;;
  restart)        stop_all; sleep 1; start_all ;;
  status)         status ;;
  url)            show_url ;;
  setup)          moonlight_setup ;;
  pin)            pin_cmd "${2:-}" "${3:-}" ;;
  gpu)            gpu_check ;;
  logs)           tail -n 50 -f "$LOG/${2:-sunshine}.log" ;;
  *) echo "$(t "Dùng" "Usage"): $0 {user|install|install-stream|install-gpu|install-apps|setup|start|stop|restart|status|url|pin <PIN>|gpu|logs [sunshine|moonlight|desktop|cloudflared|xvfb|xvfb-events]}"; exit 1 ;;
esac
