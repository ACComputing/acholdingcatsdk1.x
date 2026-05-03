#!/bin/bash
#===============================================================================
#
#   CAT SDK 1.x5.2.261.0  [C] 1999-2026  —  Nintendo Switch (devkitA64) + stack
#
#   WSL2-oriented. devkitPro: APT repo + GPG (wget -U "dkp apt") — no GitHub,
#   no git clone. Installs / upgrades switch-dev (aarch64-none-elf-gcc, libnx).
#
#===============================================================================

set -eo pipefail

readonly COPYRIGHT='CAT SDK 1.x5.2.261.0 [C] 1999-2026'

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFFOLD=1
APT_OPTS=(
    -o "Dpkg::Use-Pty=0"
    -o "Acquire::http::Timeout=60"
    -o "Acquire::Retries=5"
)

is_wsl2() {
    [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || return 1
    # WSL2 kernels usually contain "WSL2" or "microsoft-standard"; WSL1 still has Interop + microsoft
    grep -qiE 'WSL2|microsoft-standard-WSL|microsoft' /proc/sys/kernel/osrelease 2>/dev/null
}

G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
M='\033[0;35m'
W='\033[1;34m'
R='\033[0;31m'
RST='\033[0m'

if ! is_wsl2; then
    echo -e "${R}Run inside WSL2.${RST}  wsl -e bash -lc \"bash /mnt/a/@coding/catsdk1.x5.2.261.0.sh\""
    exit 1
fi

echo -e "${M}╔══════════════════════════════════════════════════════════════╗${RST}"
echo -e "${M}║${RST} ${C}${COPYRIGHT}${RST} ${M}║${RST}"
echo -e "${M}║${RST} ${Y}Switch:${RST} devkitPro devkitA64 + switch-dev (latest from mirrors) ${M}║${RST}"
echo -e "${M}╚══════════════════════════════════════════════════════════════╝${RST}"
echo -e "${W}Tip:${RST} use ~/ for projects; avoid heavy I/O on /mnt/c or /mnt/a."

mkdir -p "${HOME}/retro-dev/bin" "${HOME}/RetroSDKs/switch-projects"

# devkitpro-pacman 6.x ships dkp-pacman in /usr/bin; older layouts used /opt/devkitpro/tools/bin/
resolve_dkp_pacman() {
    if command -v dkp-pacman &>/dev/null; then command -v dkp-pacman
    elif [[ -x /opt/devkitpro/tools/bin/dkp-pacman ]]; then echo /opt/devkitpro/tools/bin/dkp-pacman
    else echo ""
    fi
}

sudo_dkp() {
    sudo env "PATH=/usr/bin:/opt/devkitpro/tools/bin:${PATH}" dkp-pacman "$@"
}

# True if meta-group exists on configured dkp mirrors (Sony groups may be absent).
dkp_group_exists() {
    local pm
    pm="$(resolve_dkp_pacman)"
    [[ -n "$pm" ]] && env "PATH=/usr/bin:/opt/devkitpro/tools/bin:${PATH}" "$pm" -Sg "$1" &>/dev/null
}

echo -e "\n${C}== APT: prerequisites ==${RST}"
sudo apt-get "${APT_OPTS[@]}" update -qq
sudo apt-get "${APT_OPTS[@]}" install -y --no-install-recommends \
    build-essential pkg-config wget curl ca-certificates \
    cmake ninja-build unzip p7zip-full \
    dasm cc65 sdcc sdcc-libraries

#-------------------------------------------------------------------------------
#  devkitPro pacman (same steps as apt.devkitpro.org installer, but apt-get -y;
#  upstream script uses bare "apt-get install" and stops on [Y/n] in automation.)
#  No GitHub — key + repo from apt.devkitpro.org with devkitPro User-Agent.
#-------------------------------------------------------------------------------
install_devkitpro_pacman() {
    [[ -n "$(resolve_dkp_pacman)" ]] && return 0
    echo -e "${C}Installing devkitPro pacman (APT repo + dkp UA)…${RST}"
    if [[ ! -e /etc/mtab ]]; then
        sudo ln -sf /proc/self/mounts /etc/mtab || true
    fi
    sudo apt-get "${APT_OPTS[@]}" update -qq
    sudo apt-get "${APT_OPTS[@]}" install -y --no-install-recommends apt-transport-https

    if [[ ! -f /usr/share/keyring/devkitpro-pub.gpg ]]; then
        sudo mkdir -p /usr/share/keyring
        local gpgtmp="${HOME}/retro-dev/devkitpro-pub.gpg"
        rm -f "$gpgtmp"
        wget -nv --timeout=60 --tries=5 --waitretry=3 \
            -U "dkp apt" \
            -O "$gpgtmp" \
            "https://apt.devkitpro.org/devkitpro-pub.gpg"
        sudo mv "$gpgtmp" /usr/share/keyring/devkitpro-pub.gpg
    fi

    if [[ ! -f /etc/apt/sources.list.d/devkitpro.list ]]; then
        echo "deb [signed-by=/usr/share/keyring/devkitpro-pub.gpg] https://apt.devkitpro.org stable main" \
            | sudo tee /etc/apt/sources.list.d/devkitpro.list >/dev/null
    fi

    sudo apt-get "${APT_OPTS[@]}" update -qq
    sudo apt-get "${APT_OPTS[@]}" install -y --no-install-recommends devkitpro-pacman
}

install_devkitpro_pacman

if [[ -z "$(resolve_dkp_pacman)" ]]; then
    echo -e "${R}dkp-pacman not found after installing devkitpro-pacman.${RST}"
    exit 1
fi

#-------------------------------------------------------------------------------
#  Nintendo Switch compiler (devkitA64) — switch-dev meta + mirror upgrade
#-------------------------------------------------------------------------------
echo -e "\n${C}== Nintendo Switch (devkitA64 / switch-dev) ==${RST}"
echo -e "${G}✓ dkp-pacman${RST}  $(resolve_dkp_pacman)"

sudo_dkp -Sy --noconfirm

# Install if toolchain binaries are missing (PATH may not include devkitA64 yet)
if [[ ! -x /opt/devkitpro/devkitA64/bin/aarch64-none-elf-gcc ]]; then
    echo -e "${Y}Installing switch-dev (aarch64-none-elf-gcc, libnx, tools)…${RST}"
    sudo_dkp -S --needed --noconfirm switch-dev
fi

# Always refresh to latest packages on mirrors (Switch toolchain, libnx, nxlink, etc.)
echo -e "${C}Upgrading devkitPro packages to latest (-Syu)…${RST}"
sudo_dkp -Syu --noconfirm

if [[ -x /opt/devkitpro/devkitA64/bin/aarch64-none-elf-gcc ]]; then
    echo -e "${G}✓ aarch64-none-elf-gcc${RST}  $(/opt/devkitpro/devkitA64/bin/aarch64-none-elf-gcc --version 2>/dev/null | head -1)"
else
    echo -e "${R}! aarch64-none-elf-gcc still missing — check: sudo_dkp -Qi switch-dev${RST}"
fi
if command -v nxlink &>/dev/null; then
    echo -e "${G}✓ nxlink${RST}"
elif [[ -x /opt/devkitpro/tools/bin/nxlink ]]; then
    echo -e "${G}✓ nxlink${RST} (devkitPro tools)"
fi

#-------------------------------------------------------------------------------
#  Optional: handheld / Sony groups (only if absent; no GitHub)
#  Install one meta-group per invocation so --noconfirm applies cleanly; skip
#  targets not present on mirrors (e.g. ps2-dev / psp-dev / ps3-dev retired).
#-------------------------------------------------------------------------------
DKP_PKGS=()
[[ ! -x /opt/devkitpro/devkitARM/bin/arm-none-eabi-gcc ]] && DKP_PKGS+=(gba-dev nds-dev 3ds-dev)
command -v ee-gcc &>/dev/null || DKP_PKGS+=(ps2-dev)
command -v psp-gcc &>/dev/null || DKP_PKGS+=(psp-dev)
command -v ppu-gcc &>/dev/null || DKP_PKGS+=(ps3-dev)
DKP_FILTERED=()
for g in "${DKP_PKGS[@]}"; do
    if dkp_group_exists "$g"; then
        DKP_FILTERED+=("$g")
    else
        echo -e "${Y}Skipping optional group (not on mirrors):${RST} $g"
    fi
done
if ((${#DKP_FILTERED[@]})); then
    echo -e "\n${C}Installing optional devkit groups:${RST} ${DKP_FILTERED[*]}"
    for g in "${DKP_FILTERED[@]}"; do
        sudo_dkp -S --needed --noconfirm "$g"
    done
fi

#-------------------------------------------------------------------------------
#  ~/.bashrc — devkitA64 on PATH
#-------------------------------------------------------------------------------
MARK="# --- CAT SDK 1.x5.2.261.0 PATH ---"
if ! grep -Fq "${MARK}" "${HOME}/.bashrc" 2>/dev/null; then
    cat >>"${HOME}/.bashrc" <<EOF

${MARK} ${COPYRIGHT}
export DEVKITPRO=/opt/devkitpro
export DEVKITA64=/opt/devkitpro/devkitA64
export PATH="\${HOME}/retro-dev/bin:\${PATH}"
export PATH="\${HOME}/RetroSDKs/gbdk/bin:\${PATH}"
export PATH="\${DEVKITPRO}/tools/bin:\${PATH}"
export PATH="\${DEVKITPRO}/devkitARM/bin:\${PATH}"
[[ -d "\${DEVKITPRO}/devkitA64/bin" ]] && export PATH="\${DEVKITPRO}/devkitA64/bin:\${PATH}"
EOF
    echo -e "\n${G}Appended PATH block to ~/.bashrc${RST}"
fi

echo -e "\n${G}═══════════════════════════════════════════════════════════════${RST}"
echo -e "${G}  ${COPYRIGHT} — Switch toolchain pass complete.${RST}"
echo -e "${G}═══════════════════════════════════════════════════════════════${RST}"
echo -e "${C}Reload:${RST}  source ~/.bashrc"
c
