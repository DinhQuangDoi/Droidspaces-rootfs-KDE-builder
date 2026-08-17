# Multi-stage build for Niri + Noctalia + Anland on Fedora 44
# Stage 1: Build anland daemon
ARG TARGETPLATFORM
FROM fedora:44 AS anland-builder

ENV DEBIAN_FRONTEND=noninteractive
ARG ANLAND_REPO=https://github.com/DinhQuangDoi/anland.git
ARG ANLAND_BRANCH=main

RUN dnf install -y --setopt=install_weak_deps=False \
    git make gcc gcc-c++ pkgconfig openssl-devel ca-certificates curl \
    && dnf clean all

WORKDIR /build
RUN git clone --depth=1 --branch ${ANLAND_BRANCH} ${ANLAND_REPO} anland
WORKDIR /anland
RUN make -C daemon -j$(nproc) && \
    mkdir -p /out/anland && \
    cp daemon/anland-daemon /out/anland/

# Stage 2: Build niri with anland backend
FROM fedora:44 AS niri-builder

ENV DEBIAN_FRONTEND=noninteractive
ARG NIRI_REPO=https://github.com/niri-wm/niri.git
ARG NIRI_TAG=v26.04

RUN dnf install -y --setopt=install_weak_deps=False \
    git curl gcc gcc-c++ make pkgconfig openssl-devel \
    wayland-devel wayland-protocols-devel \
    libxkbcommon-devel mesa-libEGL-devel mesa-libGLES-devel \
    libinput-devel libudev-devel \
    libseat-devel pipewire-devel libdrm-devel \
    ca-certificates \
    && dnf clean all

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly-2024-12-01
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /build
RUN git clone --depth=1 --branch ${NIRI_TAG} ${NIRI_REPO} niri
COPY --from=anland-builder /anland/producers/niri/overlay /anland-patch

WORKDIR /niri
RUN cp -r /anland-patch/niri/src/backend/anland.rs src/backend/ && \
    cp -r /anland-patch/niri/src/backend/anland_input.rs src/backend/ && \
    cp -r /anland-patch/niri/src/backend/mod.rs src/backend/ && \
    cp -r /anland-patch/niri/src/cli.rs src/ && \
    cp -r /anland-patch/niri/src/main.rs src/ && \
    cp -r /anland-patch/niri/src/niri.rs src/ && \
    cp -r /anland-patch/niri/Cargo.toml . && \
    cp -r /anland-patch/anland-sys .

RUN cargo build --release --bin niri && \
    mkdir -p /out/niri && \
    cp target/release/niri /out/niri/

# Stage 3: Build noctalia
FROM fedora:44 AS noctalia-builder

ENV DEBIAN_FRONTEND=noninteractive
ARG NOCTALIA_REPO=https://github.com/noctalia-dev/noctalia.git
ARG NOCTALIA_BRANCH=main

RUN dnf install -y --setopt=install_weak_deps=False \
    meson gcc-c++ just \
    wayland-devel wayland-protocols-devel \
    mesa-libEGL-devel mesa-libGLES-devel \
    freetype-devel fontconfig-devel \
    cairo-devel pango-devel harfbuzz-devel \
    libxkbcommon-devel glib2-devel \
    libsecret-devel libsodium-devel \
    sdbus-cpp-devel pipewire-devel wireplumber-devel \
    pam-devel polkit-devel libcurl-devel libwebp-devel libjxl-devel libsndfile-devel librsvg2-devel \
    libqalculate-devel libxml2-devel \
    md4c-devel tomlplusplus-devel libical-devel \
    nlohmann-json-devel stb-devel \
    jemalloc-devel \
    ninja-build pkgconfig \
    ca-certificates \
    git \
    && dnf clean all

WORKDIR /build
RUN git clone --depth=1 --branch ${NOCTALIA_BRANCH} ${NOCTALIA_REPO} noctalia
WORKDIR /noctalia

RUN meson setup build-release --buildtype=release --prefix=/usr -Dnative_optimizations=false && \
    meson compile -C build-release && \
    mkdir -p /out/noctalia && \
    DESTDIR=/out/noctalia meson install -C build-release

# Stage 4: Assemble rootfs
FROM fedora:44 AS customizer

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
ARG ENABLE_systemd257_ARG
ARG USERNAME
######################################################

ENV DEBIAN_FRONTEND=noninteractive

# 加速下载
RUN echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf && \
    echo "fastestmirror=True" >> /etc/dnf/dnf.conf && \
    echo "defaultyes=True" >> /etc/dnf/dnf.conf

# 复制自定义脚本
COPY scripts/install-usb-manager.sh /usr/local/sbin/install-droidspaces-usb-manager
COPY scripts/systemd257.sh /usr/local/sbin/systemd257
COPY scripts/install-anland-kde.sh /usr/local/sbin/install-anland-kde

# 复制 systemd services
COPY scripts/start/anland-daemon.service /etc/systemd/system/
COPY scripts/start/niri.service /etc/systemd/system/
COPY scripts/start/noctalia.service /etc/systemd/system/

RUN chmod +x /usr/local/sbin/install-anland-kde

# 安装基础依赖
RUN dnf install -y --setopt=install_weak_deps=False \
    # 核心工具组件
    bash jq dialog coreutils file findutils grep sed gawk curl wget ca-certificates bash-completion systemd-udev dbus-daemon systemd systemd-pam systemd-resolved fastfetch \
    # 用户请求的基础开发/编辑工具
    git nano sudo \
    # 网络与 SSH 工具
    openssh-server net-tools iptables iptables-legacy iputils iproute bind-utils dhcp-client \
    # 进程工具
    procps-ng \
    # 内核模块支持及语言包
    kmod tzdata tar glibc-locale-source glibc-langpack-en glibc-langpack-zh && \
    # Wayland/图形栈运行时
    dnf install -y --setopt=install_weak_deps=False \
    libwayland-client wayland libxkbcommon libdrm libinput libseat pipewire pipewire-pulse wireplumber \
    google-noto-cjk-fonts google-noto-emoji-color-fonts \
    polkit-gnome \
    alacritty rofi pcmanfm \
    lxappearance qt6ct kvantum && \
    echo "%_install_langs all" > /etc/rpm/macros.image-language-conf && \
    dnf upgrade -y && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# 复制构建产物
COPY --from=anland-builder /out/anland/anland-daemon /usr/local/bin/anland-daemon
COPY --from=niri-builder /out/niri/niri /usr/local/bin/niri
COPY --from=noctalia-builder /out/noctalia/usr/bin/noctalia /usr/local/bin/noctalia
COPY --from=noctalia-builder /out/noctalia/usr/share/noctalia /usr/local/share/noctalia

# 复制配置文件
COPY configs/noctalia/config.toml.mobile /etc/xdg/noctalia/config.toml
COPY configs/niri/kiauh.yaml.mobile /etc/xdg/niri/kiauh.yaml

RUN mkdir -p /etc/skel/.config/noctalia /etc/skel/.config/niri && \
    cp /etc/xdg/noctalia/config.toml /etc/skel/.config/noctalia/config.toml && \
    cp /etc/xdg/niri/kiauh.yaml /etc/skel/.config/niri/kiauh.yaml

# 强制配置使用 iptables-legacy
RUN ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables && \
    ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables && \
    ln -sf /usr/sbin/iptables-legacy-save /usr/sbin/iptables-save && \
    ln -sf /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore && \
    ln -sf /usr/sbin/ip6tables-legacy-save /usr/sbin/ip6tables-save && \
    ln -sf /usr/sbin/ip6tables-legacy-restore /usr/sbin/ip6tables-restore

# Locale & User
RUN if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
        echo "Asia/Shanghai" > /etc/timezone && \
        echo "LANG=zh_CN.UTF-8" > /etc/locale.conf && \
        echo "LC_ALL=zh_CN.UTF-8" >> /etc/locale.conf; \
    else \
        echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
        echo "LC_ALL=en_US.UTF-8" >> /etc/locale.conf; \
    fi && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    (userdel -r debian 2>/dev/null || true) && \
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
XDG_RUNTIME_DIR=/run/user/$(id -u)
WAYLAND_DISPLAY=wayland-0
QT_QPA_PLATFORM=wayland
GTK_THEME=Adwaita:dark
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
        jq -r '.assets[] | select(.name | test("mesa-for-android-container_.*_fedora_44_arm64\\.tar\\.gz")) | .browser_download_url' | head -1) && \
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
usermod -a -G aid_inet,aid_net_raw,input,video,tty,wheel,droidspaces-gpu ${USERNAME} || true

if [ -f /etc/default/useradd ]; then
    sed -i '/^GROUPS=/d' /etc/default/useradd
    echo 'GROUPS="aid_inet,aid_net_raw,input,video,tty"' >> /etc/default/useradd
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
GUEST_SYSTEMD_PATH="/usr/lib/systemd/system"

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

# NAT DHCP service
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

# Enable anland, niri, noctalia services
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/anland-daemon.service /etc/systemd/system/multi-user.target.wants/anland-daemon.service
ln -sf /etc/systemd/system/niri.service /etc/systemd/system/multi-user.target.wants/niri.service
ln -sf /etc/systemd/system/noctalia.service /etc/systemd/system/multi-user.target.wants/noctalia.service

if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    if ! grep -q "maxsize 50M" /etc/logrotate.conf; then
        echo "maxsize 50M" >> /etc/logrotate.conf
    fi
fi

# nsswitch for DNS
sed -i 's/^hosts:.*/hosts: files dns myhostname/' /etc/nsswitch.conf

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
        dnf install -y --setopt=install_weak_deps=False qemu-user-static; \
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

RUN dnf clean all && \
    rm -rf /var/cache/dnf/* /tmp/* /var/tmp/*

# 导出阶段
FROM scratch AS export
COPY --from=customizer / /