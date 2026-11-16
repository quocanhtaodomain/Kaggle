#!/bin/bash

# ============================================
# KaggleStream.sh
# Gaming Container Setup & Manager
# Optimized for Tesla T4 (4vCPU, 30GB RAM)
# Supports: English / Tiếng Việt
# Usage: ./KaggleStream.sh [help|install|start|restart|stop|status|log]
# ============================================

SCRIPT_VERSION="1.1.0"
LOG_FILE="/var/log/kagglestream.log"
PID_DIR="/var/run/kagglestream"

# User config
GAMER_USER="Quahnah"
GAMER_PASS="123456"

# ============================================
# LANGUAGE SETUP
# ============================================

_LANG="${LANG:-en}"
case "$_LANG" in
    vi*) UI_LANG="vi" ;;
    *)   UI_LANG="en" ;;
esac

msg() {
    local key="$1"
    if [ "$UI_LANG" = "vi" ]; then
        case "$key" in
            lang_name)          echo "Tiếng Việt" ;;
            version)            echo "Phiên bản" ;;
            inst_start)         echo "Bắt đầu cài đặt môi trường gaming..." ;;
            inst_update)        echo "Đang cập nhật hệ thống..." ;;
            inst_deps)          echo "Đang cài đặt thư viện phụ thuộc..." ;;
            inst_user)          echo "Đang tạo người dùng $GAMER_USER..." ;;
            inst_nvidia)        echo "Đang cài đặt NVIDIA Driver cho Tesla T4..." ;;
            inst_virtualgl)     echo "Đang cài đặt VirtualGL + OpenGL + Vulkan..." ;;
            inst_desktop)       echo "Đang cài đặt Openbox + LXDE Panel..." ;;
            inst_chromium)      echo "Đang cài đặt Chromium..." ;;
            inst_sunshine)      echo "Đang cài đặt Sunshine..." ;;
            inst_moonlight)     echo "Đang cài đặt Moonlight Web Stream..." ;;
            inst_polymc)        echo "Đang cài đặt PolyMC Launcher..." ;;
            inst_cloudflare)    echo "Đang cài đặt Cloudflare Tunnel..." ;;
            inst_optimize)      echo "Đang tối ưu hóa hệ thống..." ;;
            inst_cleartext)     echo "Đang cấu hình ẩn log..." ;;
            inst_done)          echo "Cài đặt hoàn tất! Chạy: ./KaggleStream.sh start" ;;
            inst_already)       echo "Đã cài đặt rồi. Dùng --force để cài lại." ;;
            start_begin)        echo "Đang khởi động môi trường gaming..." ;;
            start_pulse)        echo "Khởi động PulseAudio..." ;;
            start_xserver)      echo "Khởi động X Server (VNC)..." ;;
            start_openbox)      echo "Khởi động Openbox..." ;;
            start_sunshine)     echo "Khởi động Sunshine..." ;;
            start_moonlight)    echo "Khởi động Moonlight Web Stream..." ;;
            start_tunnels)      echo "Khởi động Cloudflare Tunnels..." ;;
            start_done)         echo "Môi trường đã sẵn sàng!" ;;
            stop_begin)         echo "Đang dừng tất cả dịch vụ..." ;;
            stop_done)          echo "Đã dừng tất cả dịch vụ." ;;
            restart_begin)      echo "Đang khởi động lại..." ;;
            status_running)     echo "Đang chạy" ;;
            status_stopped)     echo "Đã dừng" ;;
            status_title)       echo "Trạng thái dịch vụ" ;;
            err_notinstalled)   echo "Chưa cài đặt. Chạy: ./KaggleStream.sh install" ;;
            err_noroot)         echo "Lỗi: Cần quyền root để cài đặt." ;;
            warn_nvidia)        echo "Cảnh báo: nvidia-smi thất bại. GPU có thể chưa được mount." ;;
            warn_sysctl)        echo "Cảnh báo: Không thể áp dụng sysctl (bình thường trong container)." ;;
            log_title)          echo "Nhật ký hệ thống" ;;
            log_sunshine)       echo "Log Sunshine" ;;
            log_moonlight)      echo "Log Moonlight" ;;
            log_tunnel_sun)     echo "Log Tunnel Sunshine" ;;
            log_tunnel_moon)    echo "Log Tunnel Moonlight" ;;
            help_desc)          echo "Quản lý môi trường gaming container cho Tesla T4" ;;
            help_usage)         echo "Cách dùng" ;;
            help_commands)      echo "Lệnh" ;;
            help_help)          echo "Hiển thị trợ giúp này" ;;
            help_install)       echo "Cài đặt toàn bộ môi trường gaming" ;;
            help_start)         echo "Khởi động tất cả dịch vụ + Cloudflare Tunnels" ;;
            help_stop)          echo "Dừng tất cả dịch vụ" ;;
            help_restart)       echo "Khởi động lại tất cả dịch vụ" ;;
            help_status)        echo "Kiểm tra trạng thái dịch vụ" ;;
            help_log)           echo "Xem nhật ký (mặc định: 50 dòng cuối)" ;;
            help_env)           echo "Biến môi trường" ;;
            help_lang)          echo "Ngôn ngữ giao diện: vi = Tiếng Việt, en = English" ;;
            help_force)         echo "Cài lại từ đầu" ;;
            help_clearlog)      echo "Xóa toàn bộ log hệ thống" ;;
            *)                  echo "$key" ;;
        esac
    else
        case "$key" in
            lang_name)          echo "English" ;;
            version)            echo "Version" ;;
            inst_start)         echo "Starting gaming environment installation..." ;;
            inst_update)        echo "Updating system packages..." ;;
            inst_deps)          echo "Installing dependencies..." ;;
            inst_user)          echo "Creating user $GAMER_USER..." ;;
            inst_nvidia)        echo "Installing NVIDIA Driver for Tesla T4..." ;;
            inst_virtualgl)     echo "Installing VirtualGL + OpenGL + Vulkan..." ;;
            inst_desktop)       echo "Installing Openbox + LXDE Panel..." ;;
            inst_chromium)      echo "Installing Chromium..." ;;
            inst_sunshine)      echo "Installing Sunshine..." ;;
            inst_moonlight)     echo "Installing Moonlight Web Stream..." ;;
            inst_polymc)        echo "Installing PolyMC Launcher..." ;;
            inst_cloudflare)    echo "Installing Cloudflare Tunnel..." ;;
            inst_optimize)      echo "Optimizing system for gaming..." ;;
            inst_cleartext)     echo "Configuring log hiding..." ;;
            inst_done)          echo "Installation complete! Run: ./KaggleStream.sh start" ;;
            inst_already)        echo "Already installed. Use --force to reinstall." ;;
            start_begin)        echo "Starting gaming environment..." ;;
            start_pulse)        echo "Starting PulseAudio..." ;;
            start_xserver)      echo "Starting X Server (VNC)..." ;;
            start_openbox)      echo "Starting Openbox..." ;;
            start_sunshine)     echo "Starting Sunshine..." ;;
            start_moonlight)    echo "Starting Moonlight Web Stream..." ;;
            start_tunnels)      echo "Starting Cloudflare Tunnels..." ;;
            start_done)         echo "Environment is ready!" ;;
            stop_begin)         echo "Stopping all services..." ;;
            stop_done)          echo "All services stopped." ;;
            restart_begin)      echo "Restarting all services..." ;;
            status_running)     echo "Running" ;;
            status_stopped)     echo "Stopped" ;;
            status_title)       echo "Service Status" ;;
            err_notinstalled)   echo "Not installed. Run: ./KaggleStream.sh install" ;;
            err_noroot)         echo "Error: Root privileges required for installation." ;;
            warn_nvidia)        echo "Warning: nvidia-smi failed. GPU may not be mounted." ;;
            warn_sysctl)        echo "Warning: Cannot apply sysctl (normal in container)." ;;
            log_title)          echo "System Logs" ;;
            log_sunshine)       echo "Sunshine Log" ;;
            log_moonlight)      echo "Moonlight Log" ;;
            log_tunnel_sun)     echo "Sunshine Tunnel Log" ;;
            log_tunnel_moon)    echo "Moonlight Tunnel Log" ;;
            help_desc)          echo "Gaming container environment manager for Tesla T4" ;;
            help_usage)         echo "Usage" ;;
            help_commands)      echo "Commands" ;;
            help_help)          echo "Show this help message" ;;
            help_install)       echo "Install the full gaming environment" ;;
            help_start)         echo "Start all services + Cloudflare Tunnels" ;;
            help_stop)          echo "Stop all services" ;;
            help_restart)       echo "Restart all services" ;;
            help_status)        echo "Check service status" ;;
            help_log)           echo "View logs (default: last 50 lines)" ;;
            help_env)           echo "Environment variables" ;;
            help_lang)          echo "UI language: vi = Tiếng Việt, en = English" ;;
            help_force)         echo "Force reinstall" ;;
            help_clearlog)      echo "Clear all system logs" ;;
            *)                  echo "$key" ;;
        esac
    fi
}

# ============================================
# HELPERS
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}${CYAN}>>> $* ${NC}" | tee -a "$LOG_FILE"; }

mkdir -p "$PID_DIR"
mkdir -p "$(dirname $LOG_FILE)"
touch "$LOG_FILE"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "$(msg err_noroot)"
        exit 1
    fi
}

is_installed() {
    [ -f /opt/kagglestream/.installed ]
}

save_pid() {
    local name="$1"
    local pid="$2"
    echo "$pid" > "$PID_DIR/$name.pid"
}

get_pid() {
    local name="$1"
    local pidfile="$PID_DIR/$name.pid"
    if [ -f "$pidfile" ]; then
        local pid
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi
    return 1
}

service_status() {
    local name="$1"
    if get_pid "$name" > /dev/null 2>&1; then
        echo -e "${GREEN}● $(msg status_running)${NC}"
    else
        echo -e "${RED}○ $(msg status_stopped)${NC}"
    fi
}

# ============================================
# LOG HIDING / CLEANUP
# ============================================

clear_logs() {
    # Clear auth logs
    cat /dev/null > /var/log/auth.log 2>/dev/null || true
    cat /dev/null > /var/log/syslog 2>/dev/null || true
    cat /dev/null > /var/log/daemon.log 2>/dev/null || true
    cat /dev/null > /var/log/kern.log 2>/dev/null || true
    cat /dev/null > /var/log/wtmp 2>/dev/null || true
    cat /dev/null > /var/log/btmp 2>/dev/null || true
    cat /dev/null > /var/log/lastlog 2>/dev/null || true

    # Clear journald if available
    if command -v journalctl &>/dev/null; then
        journalctl --rotate 2>/dev/null || true
        journalctl --vacuum-time=1s 2>/dev/null || true
    fi

    # Clear history files
    cat /dev/null > /root/.bash_history 2>/dev/null || true
    cat /dev/null > /root/.python_history 2>/dev/null || true
    cat /dev/null > /home/${GAMER_USER}/.bash_history 2>/dev/null || true
    cat /dev/null > /home/${GAMER_USER}/.python_history 2>/dev/null || true

    # Clear vim history
    cat /dev/null > /root/.viminfo 2>/dev/null || true
    cat /dev/null > /home/${GAMER_USER}/.viminfo 2>/dev/null || true

    # Remove .lesshst
    rm -f /root/.lesshst /home/${GAMER_USER}/.lesshst 2>/dev/null || true

    # Clear kagglestream own log
    cat /dev/null > "$LOG_FILE" 2>/dev/null || true
}

setup_log_hiding() {
    # Disable bash history for root and gamer user
    for user_home in /root /home/${GAMER_USER}; do
        # Disable bash history
        cat >> "$user_home/.bashrc" << 'HISTEOF'

# Disable history logging
export HISTFILE=/dev/null
export HISTSIZE=0
export HISTFILESIZE=0
unset HISTFILE
HISTEOF

        # Disable history in .bash_profile too
        cat >> "$user_home/.bash_profile" 2>/dev/null << 'PROFEOF'
export HISTFILE=/dev/null
export HISTSIZE=0
export HISTFILESIZE=0
PROFEOF
    done

    # Configure logrotate to keep logs minimal
    cat > /etc/logrotate.d/kagglestream-hide << 'LREOF'
/var/log/auth.log {
    daily
    rotate 0
    size 0
    missingok
    create
}
/var/log/syslog {
    daily
    rotate 0
    size 0
    missingok
    create
}
LREOF

    # If rsyslog exists, reduce logging
    if [ -f /etc/rsyslog.conf ]; then
        # Comment out auth logging lines
        sed -i 's/^[^#].*auth\./#&/' /etc/rsyslog.conf 2>/dev/null || true
    fi

    # Clear current logs
    clear_logs
}

# ============================================
# USER CREATION
# ============================================

create_gamer_user() {
    # Create user with home directory
    if id "$GAMER_USER" &>/dev/null; then
        # User exists - reset password
        echo "${GAMER_USER}:${GAMER_PASS}" | chpasswd
    else
        useradd -m -s /bin/bash "$GAMER_USER"
        echo "${GAMER_USER}:${GAMER_PASS}" | chpasswd
    fi

    # Add to sudo group
    usermod -aG sudo "$GAMER_USER" 2>/dev/null || true
    usermod -aG adm "$GAMER_USER" 2>/dev/null || true
    usermod -aG video "$GAMER_USER" 2>/dev/null || true
    usermod -aG render "$GAMER_USER" 2>/dev/null || true
    usermod -aG audio "$GAMER_USER" 2>/dev/null || true
    usermod -aG dialout "$GAMER_USER" 2>/dev/null || true

    # Passwordless sudo
    echo "${GAMER_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${GAMER_USER}
    chmod 440 /etc/sudoers.d/${GAMER_USER}

    # Copy openbox config to gamer home
    mkdir -p /home/${GAMER_USER}/.config/openbox
    cp /root/.config/openbox/autostart /home/${GAMER_USER}/.config/openbox/autostart 2>/dev/null || true

    # Copy xinitrc
    cat > /home/${GAMER_USER}/.xinitrc << 'EOF'
#!/bin/bash
export DISPLAY=:0
export VGL_DISPLAY=:0
exec openbox-session
EOF
    chmod +x /home/${GAMER_USER}/.xinitrc
    chown ${GAMER_USER}:${GAMER_USER} /home/${GAMER_USER}/.xinitrc

    # Fix ownership
    chown -R ${GAMER_USER}:${GAMER_USER} /home/${GAMER_USER}/.config 2>/dev/null || true
}

# ============================================
# COMMAND: help
# ============================================

cmd_help() {
    echo -e "${BOLD}"
    echo "  ██╗  ██╗ █████╗  ██████╗  ██████╗ ██╗     ███████╗"
    echo "  ██║ ██╔╝██╔══██╗██╔════╝ ██╔════╝ ██║     ██╔════╝"
    echo "  █████╔╝ ███████║██║  ███╗██║  ███╗██║     █████╗  "
    echo "  ██╔═██╗ ██╔══██║██║   ██║██║   ██║██║     ██╔══╝  "
    echo "  ██║  ██╗██║  ██║╚██████╔╝╚██████╔╝███████╗███████╗"
    echo "  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝╚══════╝"
    echo -e "  ███████╗████████╗██████╗ ███████╗ █████╗ ███╗   ███╗${NC}"
    echo ""
    echo -e "  ${CYAN}$(msg version): ${SCRIPT_VERSION}${NC}  |  ${CYAN}$(msg lang_name)${NC}"
    echo -e "  ${CYAN}$(msg help_desc)${NC}"
    echo ""
    echo -e "${BOLD}$(msg help_usage):${NC}"
    echo "  LANG=vi ./KaggleStream.sh <command> [options]"
    echo "  LANG=en ./KaggleStream.sh <command> [options]"
    echo ""
    echo -e "${BOLD}$(msg help_commands):${NC}"
    printf "  ${GREEN}%-16s${NC} %s\n" "help"      "$(msg help_help)"
    printf "  ${GREEN}%-16s${NC} %s\n" "install"   "$(msg help_install)"
    printf "  ${GREEN}%-16s${NC} %s\n" "start"     "$(msg help_start)"
    printf "  ${GREEN}%-16s${NC} %s\n" "stop"      "$(msg help_stop)"
    printf "  ${GREEN}%-16s${NC} %s\n" "restart"   "$(msg help_restart)"
    printf "  ${GREEN}%-16s${NC} %s\n" "status"    "$(msg help_status)"
    printf "  ${GREEN}%-16s${NC} %s\n" "log"       "$(msg help_log)"
    printf "  ${GREEN}%-16s${NC} %s\n" "clearlog"  "$(msg help_clearlog)"
    echo ""
    echo -e "${BOLD}$(msg help_env):${NC}"
    printf "  ${YELLOW}%-10s${NC} %s\n" "LANG"     "$(msg help_lang)"
    echo ""
    echo -e "${BOLD}$(msg help_force):${NC}"
    echo "  LANG=vi ./KaggleStream.sh install --force"
    echo ""
}

# ============================================
# COMMAND: install
# ============================================

cmd_install() {
    check_root

    if is_installed && [ "$1" != "--force" ]; then
        warn "$(msg inst_already)"
        exit 0
    fi

    section "$(msg inst_start)"

    # --- System Update ---
    section "$(msg inst_update)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    ok "$(msg inst_update)"

    # --- Dependencies ---
    section "$(msg inst_deps)"
    apt-get install -y -qq \
        wget curl git build-essential software-properties-common \
        dbus-x11 x11-utils x11-xserver-utils x11vnc \
        pulseaudio pavucontrol alsa-utils \
        fonts-noto fonts-noto-cjk \
        vim nano htop net-tools lsof sudo \
        gnupg2 ca-certificates apt-transport-https \
        libglu1-mesa libgl1-mesa-dri libglx-mesa0 \
        libgles2-mesa libgl1-mesa-glx \
        libxcb1 libxcb-glx0 libxcb-dri2-0 libxcb-dri3-0 \
        libxrender1 libxi6 libxext6
    ok "$(msg inst_deps)"

    # --- Create Gamer User ---
    section "$(msg inst_user)"
    create_gamer_user
    ok "$(msg inst_user) ($GAMER_USER / $GAMER_PASS)"

    # --- NVIDIA Driver ---
    section "$(msg inst_nvidia)"
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb
    rm cuda-keyring_1.1-1_all.deb
    apt-get update -qq
    apt-get install -y -qq \
        nvidia-driver-535 \
        nvidia-utils-535 \
        libnvidia-encode-535 \
        libnvidia-decode-535 \
        nvidia-cuda-toolkit
    nvidia-smi || warn "$(msg warn_nvidia)"
    nvidia-smi -pm 1 || true
    ok "$(msg inst_nvidia)"

    # --- VirtualGL + OpenGL + Vulkan ---
    section "$(msg inst_virtualgl)"

    VGLVER="3.1.1"
    wget -q "https://github.com/VirtualGL/virtualgl/releases/download/${VGLVER}/virtualgl_${VGLVER}_amd64.deb" -O /tmp/virtualgl.deb
    dpkg -i /tmp/virtualgl.deb
    rm /tmp/virtualgl.deb

    apt-get install -y -qq \
        mesa-utils \
        libgl1-mesa-glx \
        libglu1-mesa \
        freeglut3 \
        libglew-dev \
        libglfw3

    apt-get install -y -qq \
        vulkan-tools \
        libvulkan1 \
        libvulkan-dev \
        mesa-vulkan-drivers \
        vulkan-validationlayers

    apt-get install -y -qq libnvidia-gl-535 || true

    /opt/VirtualGL/bin/vglserver_config -config +s +f -t || true

    ok "$(msg inst_virtualgl)"

    # --- Openbox + LXDE Panel ---
    section "$(msg inst_desktop)"
    apt-get install -y -qq \
        openbox obconf \
        lxpanel lxappearance \
        pcmanfm \
        xterm \
        tint2 nitrogen \
        tigervnc-standalone-server \
        novnc websockify

    mkdir -p /root/.config/openbox
    cat > /root/.config/openbox/autostart << 'EOF'
#!/bin/bash
lxpanel &
pcmanfm --desktop &
EOF
    chmod +x /root/.config/openbox/autostart

    cat > /root/.xinitrc << 'EOF'
#!/bin/bash
export DISPLAY=:0
export VGL_DISPLAY=:0
exec openbox-session
EOF
    chmod +x /root/.xinitrc

    # Copy config to gamer user
    mkdir -p /home/${GAMER_USER}/.config/openbox
    cp /root/.config/openbox/autostart /home/${GAMER_USER}/.config/openbox/autostart
    chown -R ${GAMER_USER}:${GAMER_USER} /home/${GAMER_USER}/.config
    ok "$(msg inst_desktop)"

    # --- Chromium ---
    section "$(msg inst_chromium)"
    apt-get install -y -qq chromium-browser chromium-codecs-ffmpeg-extra
    ok "$(msg inst_chromium)"

    # --- Sunshine ---
    section "$(msg inst_sunshine)"
    SUNSHINE_VER="v0.23.1"
    wget -q "https://github.com/LizardByte/Sunshine/releases/download/${SUNSHINE_VER}/sunshine-ubuntu-22.04-amd64.deb" -O /tmp/sunshine.deb
    apt-get install -y -qq /tmp/sunshine.deb
    rm /tmp/sunshine.deb

    mkdir -p /root/.config/sunshine
    cat > /root/.config/sunshine/sunshine.conf << 'EOF'
# Sunshine - Optimized for Tesla T4 + VirtualGL
encoder            = nvenc
adapter_name       = NVIDIA Tesla T4
output_name        = 0
min_threads        = 4
channels           = 2
fps                = 60
min_fps            = 30
nvenc_preset       = p7
nvenc_latency_mode = low
nvenc_vbv_increase = 0
min_log_level      = info
EOF

    # Copy Sunshine config to gamer user
    mkdir -p /home/${GAMER_USER}/.config/sunshine
    cp /root/.config/sunshine/sunshine.conf /home/${GAMER_USER}/.config/sunshine/sunshine.conf
    chown -R ${GAMER_USER}:${GAMER_USER} /home/${GAMER_USER}/.config/sunshine
    ok "$(msg inst_sunshine)"

    # --- Moonlight Web Stream ---
    section "$(msg inst_moonlight)"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs

    mkdir -p /opt
    if [ -d /opt/moonlight-web-stream ]; then
        git -C /opt/moonlight-web-stream pull
    else
        git clone -q https://github.com/MrCreativ3001/moonlight-web-stream.git /opt/moonlight-web-stream
    fi
    cd /opt/moonlight-web-stream
    npm install --silent
    npm run build --silent
    ok "$(msg inst_moonlight)"

    # --- PolyMC ---
    section "$(msg inst_polymc)"
    apt-get install -y -qq openjdk-17-jre openjdk-8-jre
    if ! apt-get install -y -qq polymc 2>/dev/null; then
        apt-get install -y -qq flatpak
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        flatpak install -y flathub org.polymc.PolyMC 2>/dev/null || \
            warn "PolyMC flatpak failed, install manually after start."
    fi
    ok "$(msg inst_polymc)"

    # --- Cloudflare Tunnel ---
    section "$(msg inst_cloudflare)"
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O /tmp/cloudflared.deb
    dpkg -i /tmp/cloudflared.deb
    rm /tmp/cloudflared.deb
    ok "$(msg inst_cloudflare)"

    # --- System Optimization ---
    section "$(msg inst_optimize)"

    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null || true
    fi

    cat >> /etc/sysctl.d/99-kagglestream.conf << 'EOF'
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
EOF
    sysctl -p /etc/sysctl.d/99-kagglestream.conf || warn "$(msg warn_sysctl)"

    mkdir -p /etc/pulse
    cat > /etc/pulse/daemon.conf << 'EOF'
default-sample-format = s16le
default-sample-rate = 48000
alternate-sample-rate = 44100
default-sample-channels = 2
default-fragments = 4
default-fragment-size-msec = 5
EOF

    cat > /etc/security/limits.d/99-kagglestream.conf << 'EOF'
* soft nofile 524288
* hard nofile 524288
* soft nproc 524288
* hard nproc 524288
EOF
    ok "$(msg inst_optimize)"

    # --- Log Hiding ---
    section "$(msg inst_cleartext)"
    setup_log_hiding
    ok "$(msg inst_cleartext)"

    # --- Mark installed ---
    mkdir -p /opt/kagglestream
    touch /opt/kagglestream/.installed

    # Final log clear
    clear_logs

    echo ""
    echo -e "${BOLD}${GREEN}=============================${NC}"
    echo -e "${BOLD}${GREEN}  $(msg inst_done)${NC}"
    echo -e "${BOLD}${GREEN}=============================${NC}"
    echo ""
    echo -e "  ${CYAN}User:${NC}  $GAMER_USER"
    echo -e "  ${CYAN}Pass:${NC}  $GAMER_PASS"
    echo ""
}

# ============================================
# COMMAND: start
# ============================================

cmd_start() {
    if ! is_installed; then
        error "$(msg err_notinstalled)"
        exit 1
    fi

    section "$(msg start_begin)"

    # PulseAudio
    info "$(msg start_pulse)"
    pulseaudio --start --exit-idle-time=-1 2>/dev/null || true

    # X Server / VNC
    info "$(msg start_xserver)"
    if ! get_pid "xvnc" > /dev/null 2>&1; then
        Xtigervnc :0 -screen 0 1920x1080x24 -SecurityTypes None \
            -rfbport 5900 > /tmp/kagglestream-xvnc.log 2>&1 &
        save_pid "xvnc" $!
        sleep 3
    fi
    export DISPLAY=:0

    # Openbox
    info "$(msg start_openbox)"
    if ! get_pid "openbox" > /dev/null 2>&1; then
        DISPLAY=:0 openbox-session > /tmp/kagglestream-openbox.log 2>&1 &
        save_pid "openbox" $!
        sleep 2
    fi

    # Sunshine
    info "$(msg start_sunshine)"
    if ! get_pid "sunshine" > /dev/null 2>&1; then
        DISPLAY=:0 VGL_DISPLAY=:0 sunshine > /tmp/kagglestream-sunshine.log 2>&1 &
        save_pid "sunshine" $!
        sleep 3
    fi

    # Moonlight Web Stream
    info "$(msg start_moonlight)"
    if ! get_pid "moonlight" > /dev/null 2>&1; then
        cd /opt/moonlight-web-stream
        npm run start > /tmp/kagglestream-moonlight.log 2>&1 &
        save_pid "moonlight" $!
        sleep 3
    fi

    # Cloudflare Tunnels
    section "$(msg start_tunnels)"

    if ! get_pid "tunnel-sunshine" > /dev/null 2>&1; then
        cloudflared tunnel --url https://localhost:47990 \
            > /tmp/kagglestream-tunnel-sunshine.log 2>&1 &
        save_pid "tunnel-sunshine" $!
    fi

    if ! get_pid "tunnel-moonlight" > /dev/null 2>&1; then
        cloudflared tunnel --url http://localhost:3000 \
            > /tmp/kagglestream-tunnel-moonlight.log 2>&1 &
        save_pid "tunnel-moonlight" $!
    fi

    sleep 5
    local url_sunshine url_moonlight
    url_sunshine=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' \
        /tmp/kagglestream-tunnel-sunshine.log 2>/dev/null | head -1)
    url_moonlight=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' \
        /tmp/kagglestream-tunnel-moonlight.log 2>/dev/null | head -1)

    echo ""
    echo -e "${BOLD}${GREEN}====================================${NC}"
    echo -e "${BOLD}${GREEN}  $(msg start_done)${NC}"
    echo -e "${BOLD}${GREEN}====================================${NC}"
    echo ""
    echo -e "  ${CYAN}Sunshine  Web UI:${NC} https://localhost:47990"
    echo -e "  ${CYAN}Moonlight Web:   ${NC} http://localhost:3000"
    echo ""
    if [ -n "$url_sunshine" ]; then
        echo -e "  ${GREEN}Sunshine  Tunnel:${NC} $url_sunshine"
    else
        echo -e "  ${YELLOW}Sunshine  Tunnel:${NC} (generating... check: ./KaggleStream.sh log)"
    fi
    if [ -n "$url_moonlight" ]; then
        echo -e "  ${GREEN}Moonlight Tunnel:${NC} $url_moonlight"
    else
        echo -e "  ${YELLOW}Moonlight Tunnel:${NC} (generating... check: ./KaggleStream.sh log)"
    fi
    echo ""

    # Clear logs after start
    clear_logs
}

# ============================================
# COMMAND: stop
# ============================================

cmd_stop() {
    section "$(msg stop_begin)"
    for svc in tunnel-moonlight tunnel-sunshine moonlight sunshine openbox xvnc; do
        local pid
        pid=$(get_pid "$svc" 2>/dev/null) && {
            kill "$pid" 2>/dev/null && info "Stopped: $svc (PID $pid)"
            rm -f "$PID_DIR/$svc.pid"
        } || true
    done
    pkill -f "cloudflared" 2>/dev/null || true
    pkill -f "moonlight-web-stream" 2>/dev/null || true
    pkill -f "sunshine" 2>/dev/null || true
    pkill -f "openbox" 2>/dev/null || true
    pkill -f "Xtigervnc" 2>/dev/null || true
    ok "$(msg stop_done)"

    # Clear logs after stop
    clear_logs
}

# ============================================
# COMMAND: restart
# ============================================

cmd_restart() {
    section "$(msg restart_begin)"
    cmd_stop
    sleep 2
    cmd_start
}

# ============================================
# COMMAND: status
# ============================================

cmd_status() {
    echo ""
    echo -e "${BOLD}${CYAN}  $(msg status_title)${NC}"
    echo "  ─────────────────────────────────────"
    printf "  %-22s %s\n" "X Server (VNC)"        "$(service_status xvnc)"
    printf "  %-22s %s\n" "Openbox"               "$(service_status openbox)"
    printf "  %-22s %s\n" "Sunshine"              "$(service_status sunshine)"
    printf "  %-22s %s\n" "Moonlight Web Stream" "$(service_status moonlight)"
    printf "  %-22s %s\n" "Tunnel (Sunshine)"     "$(service_status tunnel-sunshine)"
    printf "  %-22s %s\n" "Tunnel (Moonlight)"    "$(service_status tunnel-moonlight)"
    echo "  ─────────────────────────────────────"
    echo ""

    # GPU status
    echo -e "  ${BOLD}GPU:${NC}"
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total \
            --format=csv,noheader,nounits 2>/dev/null | \
            awk -F',' '{printf "  %-20s Temp:%s°C  GPU:%s%%  VRAM:%s%%  Mem:%sMB/%sMB\n",$1,$2,$3,$5,$6,$7}' \
            || echo "  nvidia-smi unavailable"
    else
        echo "  NVIDIA driver not found"
    fi

    # Tunnel URLs
    echo ""
    echo -e "  ${BOLD}Cloudflare Tunnels:${NC}"
    local url_sun url_moon
    url_sun=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' \
        /tmp/kagglestream-tunnel-sunshine.log 2>/dev/null | head -1)
    url_moon=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' \
        /tmp/kagglestream-tunnel-moonlight.log 2>/dev/null | head -1)
    echo "  Sunshine : ${url_sun:-N/A}"
    echo "  Moonlight: ${url_moon:-N/A}"
    echo ""
}

# ============================================
# COMMAND: log
# ============================================

cmd_log() {
    local lines="${1:-50}"
    echo ""
    echo -e "${BOLD}${CYAN}=== $(msg log_sunshine) ===${NC}"
    tail -n "$lines" /tmp/kagglestream-sunshine.log 2>/dev/null || echo "(no log)"

    echo ""
    echo -e "${BOLD}${CYAN}=== $(msg log_moonlight) ===${NC}"
    tail -n "$lines" /tmp/kagglestream-moonlight.log 2>/dev/null || echo "(no log)"

    echo ""
    echo -e "${BOLD}${CYAN}=== $(msg log_tunnel_sun) ===${NC}"
    tail -n "$lines" /tmp/kagglestream-tunnel-sunshine.log 2>/dev/null || echo "(no log)"

    echo ""
    echo -e "${BOLD}${CYAN}=== $(msg log_tunnel_moon) ===${NC}"
    tail -n "$lines" /tmp/kagglestream-tunnel-moonlight.log 2>/dev/null || echo "(no log)"

    echo ""
    echo -e "${BOLD}${CYAN}=== $(msg log_title) (kagglestream) ===${NC}"
    tail -n "$lines" "$LOG_FILE" 2>/dev/null || echo "(no log)"
}

# ============================================
# COMMAND: clearlog
# ============================================

cmd_clearlog() {
    section "$(msg inst_cleartext)"
    clear_logs
    ok "$(msg inst_cleartext)"
}

# ============================================
# ENTRYPOINT
# ============================================

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    help|--help|-h)  cmd_help ;;
    install)         cmd_install "$@" ;;
    start)           cmd_start ;;
    stop)            cmd_stop ;;
    restart)         cmd_restart ;;
    status)          cmd_status ;;
    log)             cmd_log "$@" ;;
    clearlog)        cmd_clearlog ;;
    *)
        error "Unknown command: $COMMAND"
        echo ""
        cmd_help
        exit 1
        ;;
esac
