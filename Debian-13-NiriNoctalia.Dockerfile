# Multi-stage build for Niri + Noctalia + Anland on Debian 13 (Trixie)
# Stage 1: Build niri (with anland backend) directly from the niri-anland fork.
# niri-anland is a proper fork of niri-wm/niri; the anland branch carries the
# backend + anland-sys + color/cursor/blink fixes. No overlay/patch dance.
ARG TARGETPLATFORM
FROM debian:trixie AS niri-builder

ENV DEBIAN_FRONTEND=noninteractive
ARG NIRI_ANLAND_REPO=https://github.com/DinhQuangDoi/niri-anland.git
ARG NIRI_ANLAND_REF=26.4.0-anland.5

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl build-essential pkg-config libssl-dev libwayland-dev wayland-protocols \
    libxkbcommon-dev libegl-dev libgles2-mesa-dev libinput-dev libudev-dev \
    libseat-dev libpipewire-0.3-dev libdrm-dev libgbm-dev libpango1.0-dev \
    libdisplay-info-dev libclang-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Rust (stable 1.87, matches niri-anland fork CI)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.87
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /build
# Clone the niri-anland fork at the pinned release tag (self-contained: backend +
# anland-sys are already in the tree, so there is nothing to patch).
RUN git clone --depth=1 --branch ${NIRI_ANLAND_REF} ${NIRI_ANLAND_REPO} niri

WORKDIR /build/niri
RUN cargo build --release --bin niri && \
    mkdir -p /out/niri && \
    cp target/release/niri /out/niri/

# Stage 3: Build noctalia
FROM debian:trixie AS noctalia-builder

ENV DEBIAN_FRONTEND=noninteractive
ARG NOCTALIA_REPO=https://github.com/noctalia-dev/noctalia.git
ARG NOCTALIA_BRANCH=a4575781d7e9c432a58832b04e0cda310bd22b71

RUN apt-get update && apt-get install -y --no-install-recommends \
    meson g++ just \
    libwayland-dev wayland-protocols \
    libegl-dev libgles-dev \
    libfreetype-dev libfontconfig-dev \
    libcairo2-dev libpango1.0-dev libharfbuzz-dev \
    libxkbcommon-dev libglib2.0-dev \
    libsecret-1-dev libsodium-dev \
    libsdbus-c++-dev libpipewire-0.3-dev libwireplumber-0.5-dev \
    libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev \
    libcurl4-gnutls-dev libwebp-dev libjxl-dev libsndfile1-dev librsvg2-dev \
    libqalculate-dev libxml2-dev \
    libmd4c-dev libtomlplusplus-dev libical-dev \
    nlohmann-json3-dev libstb-dev \
    libjemalloc-dev \
    ninja-build pkg-config \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone ${NOCTALIA_REPO} noctalia && git -C noctalia checkout ${NOCTALIA_BRANCH}
WORKDIR /build/noctalia

RUN meson setup build-release --buildtype=release --prefix=/usr -Dnative_optimizations=false && \
    meson compile -C build-release && \
    mkdir -p /out/noctalia && \
    DESTDIR=/out/noctalia meson install -C build-release

# Stage 4: Assemble rootfs
FROM debian:trixie AS customizer

#######################################################
ARG BUILD_KDE
ARG BUILD_KDE_plus
ARG PulseAudio
ARG ENABLE_zh_tz_ARG
ARG ENABLE_binfmt_ARG
ARG ENABLE_yj_ARG
ARG ENABLE_mesa_ARG
ARG ENABLE_kfgj_ARG
ARG ENABLE_zip_ARG
ARG ENABLE_docker_ARG
ARG ENABLE_srf_ARG
ARG ENABLE_tmoe_ARG
ARG ENABLE_anland_kde_ARG
ARG ENABLE_8gen2_wayland_ARG
ARG ENABLE_nosnap_ARG
ARG ENABLE_systemd257_ARG
ARG USERNAME
######################################################

ENV DEBIAN_FRONTEND=noninteractive

# 启用 APT 并行连接
RUN printf '%s\n' \
    'Acquire::Queue-Mode "host";' \
    'Acquire::http::Pipeline-Depth "10";' \
    'Acquire::https::Pipeline-Depth "10";' \
    'Acquire::Retries "3";' \
    > /etc/apt/apt.conf.d/99parallel-downloads

# 复制自定义脚本
COPY scripts/download-firmware /usr/local/bin/
COPY scripts/systemd257.sh /usr/local/sbin/systemd257
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh
COPY scripts/install-usb-manager.sh /usr/local/sbin/install-droidspaces-usb-manager

RUN chmod +x /usr/local/bin/download-firmware /etc/profile.d/ds-aliases.sh

# 复制 systemd services
COPY scripts/start/niri.service /etc/systemd/system/
COPY scripts/start/noctalia.service /etc/systemd/system/

# 安装基础依赖
RUN sed -i 's/main/main contrib non-free/g' /etc/apt/sources.list 2>/dev/null || \
    sed -i 's/Components: main/Components: main contrib non-free/g' /etc/apt/sources.list.d/debian.sources 2>/dev/null && \
    apt-get update && \
    apt-get upgrade -y

# 安装运行时依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # 核心工具组件
    bash jq dialog coreutils file findutils grep sed gawk curl wget ca-certificates locales bash-completion udev dbus systemd-sysv systemd-resolved fastfetch \
    # 基础开发/编辑工具
    git nano sudo \
    # 网络与 SSH 工具
    openssh-server net-tools iptables iputils-ping iproute2 dnsutils \
    # 进程工具
    procps \
    # 内核模块支持
    kmod tzdata tar \
    # Wayland/图形栈
    libwayland-client0 libwayland-server0 libwayland-egl1 libegl1 libgles2 \
    libxkbcommon0 libdrm2 libinput10 libudev1 libseat1 \
    libdisplay-info3 \
    # Noctalia runtime libs
    libsdbus-c++-dev libsodium-dev libsecret-1-dev \
    libpolkit-agent-1-dev libpolkit-gobject-1-dev libwireplumber-0.5-dev \
    libqalculate-dev libmd4c-dev libtomlplusplus-dev libical-dev \
    libwebp-dev libjxl-dev librsvg2-dev libjemalloc-dev \
    pipewire pipewire-pulse wireplumber \
    # 字体
    fonts-noto-cjk fonts-noto-color-emoji \
    # 实用工具
    alacritty rofi pcmanfm \
    # 主题工具
    lxappearance qt6ct \
    && apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 复制构建产物
COPY --from=niri-builder /out/niri/niri /usr/local/bin/niri
COPY --from=noctalia-builder /out/noctalia/usr/bin/noctalia /usr/local/bin/noctalia
COPY --from=noctalia-builder /out/noctalia/usr/share/noctalia /usr/local/share/noctalia

# 复制配置文件
COPY configs/noctalia/config.toml.mobile /etc/xdg/noctalia/config.toml
COPY configs/niri/config.kdl.mobile /etc/xdg/niri/config.kdl
COPY configs/niri/kiauh.yaml.mobile /etc/xdg/niri/kiauh.yaml

RUN mkdir -p /etc/skel/.config/noctalia /etc/skel/.config/niri && \
    cp /etc/xdg/noctalia/config.toml /etc/skel/.config/noctalia/config.toml && \
    cp /etc/xdg/niri/config.kdl /etc/skel/.config/niri/config.kdl && \
    cp /etc/xdg/niri/kiauh.yaml /etc/skel/.config/niri/kiauh.yaml

# 强制配置使用 iptables-legacy
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Locale & User
RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        export DEBIAN_FRONTEND=noninteractive && \
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
        echo "Asia/Shanghai" > /etc/timezone && \
        dpkg-reconfigure -f noninteractive tzdata && \
        sed -i '/zh_CN.UTF-8/s/^# //' /etc/locale.gen && \
        locale-gen && \
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8; \
    else \
        locale-gen && \
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
    fi && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    deluser --remove-home debian || true && \
    useradd -m -s /bin/bash ${USERNAME} && echo "${USERNAME}:1234" | chpasswd

# 安装 Droidspaces USB Manager
RUN /usr/local/sbin/install-droidspaces-usb-manager --user "${USERNAME}"

# 环境变量
RUN cat <<'EOF' > /etc/environment
XCURSOR_SIZE=48
ANLAND_SOCKET=/run/display.sock
ANLAND_DRM_DEVICE=/dev/dri/renderD128
MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1
FD_DEV_FEATURES=enable_tp_ubwc_flag_hint=1
XDG_RUNTIME_DIR=/run/user/1000
XDG_SESSION_TYPE=wayland
WAYLAND_DISPLAY=wayland-1
QT_QPA_PLATFORM=wayland
GTK_THEME=Adwaita:dark
GTK_A11Y=none
NO_AT_BRIDGE=1
TMPDIR=/tmp
EOF

# Audio
RUN if [ "$PulseAudio" = "socket" ]; then \
        echo "PULSE_SERVER=unix:/tmp/.pulse-socket" >> /etc/environment; \
    elif [ "$PulseAudio" = "tcp" ]; then \
        echo "PULSE_SERVER=tcp:127.0.0.1:4713" >> /etc/environment; \
    fi

# Mesa 驱动适配
RUN if [ "$ENABLE_mesa_ARG" = "true" ]; then \
        echo "--> [开启] 正在下载并安装最新版 Mesa 驱动..." && \
        URL=$(curl -s https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest | \
        jq -r '.assets[] | select(.name | test("mesa-for-android-container_.*_debian_trixie_arm64\\.tar\\.gz")) | .browser_download_url' | head -1) && \
        if [ -z "$URL" ] || [ "$URL" = "null" ]; then echo "获取下载链接失败"; exit 1; fi && \
        wget -q --tries=5 --waitretry=3 -O /tmp/mesa.tar.gz "$URL" && \
        tar -zxf /tmp/mesa.tar.gz -C / && \
        rm /tmp/mesa.tar.gz && \
        ldconfig; \
    else \
        echo "--> [跳过] 未开启 Mesa 驱动安装"; \
    fi

# DHCP 网络配置
RUN mkdir -p /etc/systemd/network && \
    cat <<'EOF' > /etc/systemd/network/10-eth-dhcp.network
[Match]
Name=eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
UseDNS=yes
UseDomains=yes
RouteMetric=100
EOF

# Android 兼容性修复
RUN <<'EOF_RUN'
# Android 网络权限组
grep -q '^aid_inet:' /etc/group     || echo 'aid_inet:x:3003:'    >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

getent group droidspaces-gpu >/dev/null || groupadd -g 786 -r droidspaces-gpu
usermod -a -G aid_inet,aid_net_raw,input,video,tty,droidspaces-gpu root || true
usermod -a -G aid_inet,aid_net_raw,input,video,tty,sudo,droidspaces-gpu ${USERNAME} || true

grep -q '^_apt:' /etc/passwd && usermod -g aid_inet _apt || true

if [ -f /etc/adduser.conf ]; then
    sed -i '/^EXTRA_GROUPS=/d; /^ADD_EXTRA_GROUPS=/d' /etc/adduser.conf
    echo 'ADD_EXTRA_GROUPS=1' >> /etc/adduser.conf
    echo 'EXTRA_GROUPS="aid_inet aid_net_raw input video tty"' >> /etc/adduser.conf
fi

# Systemd 修复
ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

cat >> /etc/systemd/journald.conf << 'EOT'
[Journal]
ReadKMsg=no
Audit=no
Storage=volatile
EOT

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/ds-logging.conf << 'EOT'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
MaxLevelStore=info
EOT

mkdir -p /etc/systemd/system/multi-user.target.wants
GUEST_SYSTEMD_PATH="/lib/systemd/system"

if [ -f "$GUEST_SYSTEMD_PATH/dbus.service" ]; then
    ln -sf "$GUEST_SYSTEMD_PATH/dbus.service" "/etc/systemd/system/multi-user.target.wants/dbus.service"
fi

if [ "$ENABLE_yj_ARG" = "true" ]; then
    for service in systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
        if [ -f "$GUEST_SYSTEMD_PATH/$service" ]; then
            ln -sf "$GUEST_SYSTEMD_PATH/$service" "/etc/systemd/system/multi-user.target.wants/$service"
        fi
    done
else
    for service in systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
        ln -sf /dev/null "/etc/systemd/system/$service"
    done
fi

mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOF

mkdir -p /etc/systemd/system/systemd-udev-trigger.service.d
cat > /etc/systemd/system/systemd-udev-trigger.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty --subsystem-match=net
EOF

for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service systemd-udevd-kernel.socket systemd-udevd-control.socket; do
    mkdir -p "/etc/systemd/system/${unit}.d"
    printf "[Unit]\nConditionPathIsReadWrite=\n" > "/etc/systemd/system/${unit}.d/99-readonly-fix.conf"
done

for unit in NetworkManager.service dhcpcd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-netmode-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -qE 'net_mode=(nat|gateway)' /run/droidspaces/container.config"
EOF
    fi
done

for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-hwaccess-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -q 'enable_hw_access=1' /run/droidspaces/container.config"
EOF
    fi
done

# DHCP service for NAT
cat > /etc/systemd/system/ds-dhcp.service << 'EOF_DHCP'
[Unit]
Description=Droidspaces NAT DHCP (Root Bypass)
After=network.target

[Service]
Type=forking
ExecCondition=/bin/sh -c "grep -qE 'net_mode=(nat|gateway)' /run/droidspaces/container.config"
ExecStart=/usr/sbin/dhclient
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF_DHCP
ln -sf /etc/systemd/system/ds-dhcp.service /etc/systemd/system/multi-user.target.wants/ds-dhcp.service

# Enable niri, noctalia services
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/niri.service /etc/systemd/system/multi-user.target.wants/niri.service
ln -sf /etc/systemd/system/noctalia.service /etc/systemd/system/multi-user.target.wants/noctalia.service

if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    if ! grep -q "maxsize 50M" /etc/logrotate.conf; then
        echo "maxsize 50M" >> /etc/logrotate.conf
    fi
fi

echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces
EOF_RUN

# binfmt support
COPY scripts/binfmt/qemu-binfmt-register.sh /usr/local/bin/
COPY scripts/binfmt/qemu-binfmt-register.service /etc/systemd/system/
RUN if [ "$ENABLE_binfmt_ARG" = "false" ]; then \
        rm -rf /usr/local/bin/qemu-binfmt-register.sh && \
        rm -rf /etc/systemd/system/qemu-binfmt-register.service ; \
    fi

RUN if [ "$ENABLE_binfmt_ARG" = "true" ]; then \
        chmod +x /usr/local/bin/qemu-binfmt-register.sh && \
        chmod 644 /etc/systemd/system/qemu-binfmt-register.service && \
        mkdir -p /etc/systemd/system/multi-user.target.wants && \
        ln -sf /etc/systemd/system/qemu-binfmt-register.service /etc/systemd/system/multi-user.target.wants/qemu-binfmt-register.service && \
        (apt-get purge -y qemu-* binfmt-support || true) && \
        apt-get autoremove -y && \
        apt-get autoclean && \
        rm -rf /var/lib/binfmts/* /etc/binfmt.d/* /usr/lib/binfmt.d/qemu-* && \
        apt-get update && \
        apt-get install -y qemu-user-static binfmt-support && \
        dpkg --add-architecture amd64 && \
        apt-get update && \
        apt-get install -y libc6:amd64; \
    else \
        rm -f /usr/local/bin/qemu-binfmt-register.sh /etc/systemd/system/qemu-binfmt-register.service; \
    fi

# systemd 257 兼容
RUN if [ "$ENABLE_systemd257_ARG" = "true" ]; then \
        bash /usr/local/sbin/systemd257; \
    else \
        echo "--> [跳过] 未启用 systemd 257 旧内核兼容"; \
    fi && \
    rm -f /usr/local/sbin/systemd257

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 导出阶段
FROM scratch AS export
COPY --from=customizer / /