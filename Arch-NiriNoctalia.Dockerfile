# Multi-stage build for Niri + Noctalia + Anland on Arch Linux ARM
# Stage 1: Clone anland source (provides the niri backend patch)
ARG TARGETPLATFORM
FROM ogarcia/archlinux AS anland-source

ENV DEBIAN_FRONTEND=noninteractive
ARG ANLAND_REPO=https://github.com/DinhQuangDoi/anland.git
ARG ANLAND_BRANCH=main

RUN pacman -Sy --noconfirm --needed \
    git ca-certificates \
    && rm -rf /var/cache/pacman/pkg/*

WORKDIR /anland
RUN git clone --depth=1 --branch ${ANLAND_BRANCH} ${ANLAND_REPO} . && \
    mkdir -p /out/patch && \
    cp -r producers/niri/overlay/niri /out/patch/niri && \
    cp -r producers/niri/anland-sys /out/patch/anland-sys

# Stage 2: Build niri with anland backend
FROM ogarcia/archlinux AS niri-builder

ENV DEBIAN_FRONTEND=noninteractive
ARG NIRI_REPO=https://github.com/niri-wm/niri.git
ARG NIRI_TAG=v26.04

RUN pacman -Sy --noconfirm --needed \
    git curl base-devel pkgconf openssl \
    wayland wayland-protocols \
    libxkbcommon mesa libinput systemd \
    libseat pipewire libdrm libgbm pango libdisplay-info \
    && rm -rf /var/cache/pacman/pkg/*

# Install Rust (stable 1.87, matches anland fork CI)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.87
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /build
RUN git clone --depth=1 --branch ${NIRI_TAG} ${NIRI_REPO} niri
COPY --from=anland-source /out/patch /anland-patch

WORKDIR /build/niri
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
FROM ogarcia/archlinux AS noctalia-builder

ENV DEBIAN_FRONTEND=noninteractive
ARG NOCTALIA_REPO=https://github.com/noctalia-dev/noctalia.git
ARG NOCTALIA_BRANCH=main

RUN pacman -Sy --noconfirm --needed \
    meson gcc just \
    wayland wayland-protocols \
    mesa freetype2 fontconfig \
    cairo pango harfbuzz \
    libxkbcommon glib2 \
    libsecret libsodium \
    sdbus-cpp pipewire wireplumber \
    pam polkit curl libwebp libjxl libsndfile librsvg \
    libqalculate libxml2 \
    md4c tomlplusplus libical \
    nlohmann-json stb \
    jemalloc \
    ninja pkgconf \
    ca-certificates \
    git \
    && rm -rf /var/cache/pacman/pkg/*

WORKDIR /build
RUN git clone --depth=1 --branch ${NOCTALIA_BRANCH} ${NOCTALIA_REPO} noctalia
WORKDIR /build/noctalia

RUN meson setup build-release --buildtype=release --prefix=/usr -Dnative_optimizations=false && \
    meson compile -C build-release && \
    mkdir -p /out/noctalia && \
    DESTDIR=/out/noctalia meson install -C build-release

# Stage 4: Assemble rootfs
FROM ogarcia/archlinux AS customizer

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

# 复制自定义脚本
COPY scripts/install-usb-manager.sh /usr/local/sbin/install-droidspaces-usb-manager
COPY scripts/systemd257.sh /usr/local/sbin/systemd257
COPY scripts/install-anland-kde.sh /usr/local/sbin/install-anland-kde

# 复制 systemd services
COPY scripts/start/niri.service /etc/systemd/system/
COPY scripts/start/noctalia.service /etc/systemd/system/

RUN chmod +x /usr/local/sbin/install-anland-kde && \
    sed -i '/^#ParallelDownloads/s/^#//' /etc/pacman.conf && \
    sed -i '/NoExtract.*locale/d' /etc/pacman.conf && \
    sed -i '/NoExtract.*i18n/d' /etc/pacman.conf && \
    pacman -Sy --noconfirm archlinux-keyring glibc && \
    pacman -Su --noconfirm

# 安装运行时依赖
RUN pacman -S --noconfirm --needed \
    # 核心工具组件
    bash jq dialog coreutils file findutils grep sed gawk curl wget ca-certificates bash-completion dbus systemd pam fastfetch logrotate \
    # 基础开发/编辑工具
    git nano sudo \
    # 网络与 SSH 工具
    openssh net-tools iptables iputils iproute2 bind \
    # 进程工具
    procps-ng \
    # 内核模块支持
    kmod tzdata tar \
    # Wayland/图形栈
    wayland libxkbcommon mesa libinput libseat pipewire wireplumber \
    noto-fonts-cjk noto-fonts-emoji \
    alacritty rofi pcmanfm \
    lxappearance qt6ct && \
    pacman -Sc --noconfirm

# 复制构建产物
COPY --from=niri-builder /out/niri/niri /usr/local/bin/niri
COPY --from=noctalia-builder /out/noctalia/usr/bin/noctalia /usr/local/bin/noctalia
COPY --from=noctalia-builder /out/noctalia/usr/share/noctalia /usr/local/share/noctalia

# 复制配置文件
COPY configs/noctalia/config.toml.mobile /etc/xdg/noctalia/config.toml
COPY configs/niri/kiauh.yaml.mobile /etc/xdg/niri/kiauh.yaml

RUN mkdir -p /etc/skel/.config/noctalia /etc/skel/.config/niri && \
    cp /etc/xdg/noctalia/config.toml /etc/skel/.config/noctalia/config.toml && \
    cp /etc/xdg/niri/kiauh.yaml /etc/skel/.config/niri/kiauh.yaml

# 配置 Locale 与 SSH
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
        echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen && \
        locale-gen && \
        echo "LANG=zh_CN.UTF-8" > /etc/locale.conf && \
        echo "LC_ALL=zh_CN.UTF-8" >> /etc/locale.conf; \
    else \
        locale-gen && \
        echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
        echo "LC_ALL=en_US.UTF-8" >> /etc/locale.conf; \
    fi && \
    mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    userdel -r alarm 2>/dev/null || true && \
    useradd -m -s /bin/bash ${USERNAME} && echo "${USERNAME}:1234" | chpasswd && \
    systemctl enable sshd

# 为所有 Arch RootFS 安装 Droidspaces USB Manager
RUN /usr/local/sbin/install-droidspaces-usb-manager --user "${USERNAME}"

# 为 droidspaces 的 su/su -l 入口建立完整的 systemd 用户会话
RUN for pam_file in /etc/pam.d/su /etc/pam.d/su-l; do \
        if ! grep -qE '^[[:space:]-]*session[[:space:]].*pam_systemd\.so' "$pam_file"; then \
            sed -i '/^[[:space:]]*session[[:space:]].*pam_unix\.so/a\session        optional        pam_systemd.so' "$pam_file"; \
        fi; \
    done && \
    grep -qE '^[[:space:]]*session[[:space:]].*pam_env\.so' /etc/pam.d/su-l || \
        echo 'session        required        pam_env.so' >> /etc/pam.d/su-l

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
XWAYLAND_GBM_DEVICE=/dev/dri/renderD128
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
        jq -r '.assets[] | select(.name | test("mesa-for-android-container_.*_archlinux_arm64\\.tar")) | .browser_download_url' | head -1) && \
        if [ -z "$URL" ] || [ "$URL" = "null" ]; then echo "获取下载链接失败"; exit 1; fi && \
        wget -q --tries=5 --waitretry=3 -O /tmp/mesa.tar "$URL" && \
        tar -xf /tmp/mesa.tar -C /tmp && \
        cp /etc/pacman.conf /tmp/pacman-nosig.conf && \
        sed -i 's/.*SigLevel.*/SigLevel = Never/g' /tmp/pacman-nosig.conf && \
        pacman --config /tmp/pacman-nosig.conf -U --noconfirm /tmp/*.pkg.tar.* && \
        rm -f /tmp/mesa.tar /tmp/*.pkg.tar.* /tmp/pacman-nosig.conf /tmp/*.sig ; \
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

# Arch sudo 权限
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

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
        pacman -S --noconfirm --needed qemu-user qemu-user-binfmt && \
        rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* ; \
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

RUN rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*

# 导出阶段
FROM scratch AS export
COPY --from=customizer / /