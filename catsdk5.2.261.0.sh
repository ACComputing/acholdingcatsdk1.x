#!/bin/bash
#===============================================================================
#
#   AC'S TWEAKER 1.0  [C] 1999-2026  —  All consoles: Atari → PlayStation 5
#
#   Optimized for WSL2: noninteractive apt, faster pacman sync, --needed,
#   resilient downloads. No github.com / no git clone.
#
#===============================================================================

set -eo pipefail

readonly COPYRIGHT='AC'"'"'S TWEAKER 1.0 [C] 1999-2026'

# --- WSL2 / Debian: avoid debconf TTY and speed up apt over virtualized I/O ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_OPTS=(
    -o "Dpkg::Use-Pty=0"
    -o "Acquire::http::Timeout=45"
    -o "Acquire::Retries=4"
)

is_wsl() {
    [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] \
        || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

wsl_hint() {
    if is_wsl; then
        echo -e "\033[0;36m[WSL2]\033[0m Keep projects under ~/ (ext4), not /mnt/c — much faster builds & fewer apt/dpkg quirks."
    fi
}

mkdir -p "${HOME}/retro-dev/bin" "${HOME}/RetroSDKs"

DKP_PM="/opt/devkitpro/tools/bin/dkp-pacman"
sudo_dkp() { sudo env "PATH=/opt/devkitpro/tools/bin:${PATH}" "${DKP_PM}" "$@"; }

G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
M='\033[0;35m'
W='\033[1;34m'
RST='\033[0m'

banner() {
    echo -e "${M}"
    cat <<'BAN'
   ___    ____   _________________________________
  / _ |  / __/  /_  __/ __/_  __/ ____/ __/_  __/
 / __ | _\ \    / / / _/  / / / __// _/  / /   
/_/ |_|/___/   /_/ /_/   /_/ /_/ /___/ /_/    
BAN
    echo -e "${RST}${C}${COPYRIGHT}${RST}"
    if is_wsl; then
        echo -e "${W}Runtime: WSL2 (Linux $(uname -r))${RST}"
    fi
    echo -e "${Y}Targets: Atari 2600/7800, NES, Game Boy/Color, GBA, NDS, 3DS, N64,${RST}"
    echo -e "${Y}         PS2, PSP, PS3, PS4, PS5  (PS4/PS5: local SDK layout only)${RST}"
    echo ""
}

banner
wsl_hint

echo -e "${C}== Base build tools (apt) ==${RST}"
sudo apt-get "${APT_OPTS[@]}" update -qq
sudo apt-get "${APT_OPTS[@]}" install -y --no-install-recommends \
    build-essential pkg-config wget curl ca-certificates \
    cmake ninja-build unzip p7zip-full \
    dasm cc65 sdcc sdcc-libraries

#-------------------------------------------------------------------------------
#  Atari 2600 / 7800  —  dasm (apt)
#-------------------------------------------------------------------------------
echo -e "\n${C}== Atari 2600 / 7800 ==${RST}"
command -v dasm >/dev/null && echo -e "${G}✓ dasm${RST}"

#-------------------------------------------------------------------------------
#  NES / Famicom  —  cc65 (apt)
#-------------------------------------------------------------------------------
echo -e "\n${C}== NES ==${RST}"
command -v cl65 >/dev/null && echo -e "${G}✓ cc65 (cl65)${RST}"

#-------------------------------------------------------------------------------
#  Game Boy / Game Boy Color  —  SDCC (apt)
#-------------------------------------------------------------------------------
echo -e "\n${C}== Game Boy / GBC ==${RST}"
if command -v sdcc >/dev/null; then
    echo -e "${G}✓ sdcc (Game Boy: SM83 port — see sdcc(1) / SDCC manual)${RST}"
fi
echo -e "${Y}Tip: Optional GBDK → ~/RetroSDKs/gbdk/ then add bin to PATH.${RST}"

#-------------------------------------------------------------------------------
#  GBA / NDS / 3DS / PS2 / PSP / PS3  —  devkitPro (apt.devkitpro.org)
#-------------------------------------------------------------------------------
echo -e "\n${C}== GBA / NDS / 3DS / PS2 / PSP / PS3 (devkitPro) ==${RST}"
DKPRO_DEB_URL="https://apt.devkitpro.org/devkitpro-pacman.amd64.deb"
if [[ ! -x "${DKP_PM}" ]]; then
    echo -e "${C}Fetching devkitPro pacman package…${RST}"
    wget --timeout=45 --tries=4 --waitretry=2 -nv \
        -O "${HOME}/retro-dev/devkitpro-pacman.amd64.deb" "${DKPRO_DEB_URL}"
    sudo dpkg -i "${HOME}/retro-dev/devkitpro-pacman.amd64.deb"
    rm -f "${HOME}/retro-dev/devkitpro-pacman.amd64.deb"
fi

# One DB refresh + one transaction: fewer round-trips on WSL2 / 9p mounts
DKP_PKGS=()
[[ ! -x /opt/devkitpro/devkitARM/bin/arm-none-eabi-gcc ]] && DKP_PKGS+=(gba-dev nds-dev 3ds-dev)
command -v ee-gcc &>/dev/null || DKP_PKGS+=(ps2-dev)
command -v psp-gcc &>/dev/null || DKP_PKGS+=(psp-dev)
command -v ppu-gcc &>/dev/null || DKP_PKGS+=(ps3-dev)

if ((${#DKP_PKGS[@]})); then
    echo -e "${C}devkitPro: syncing DB and installing: ${DKP_PKGS[*]}${RST}"
    sudo_dkp -Sy --noconfirm
    sudo_dkp -S --needed --noconfirm "${DKP_PKGS[@]}"
    echo -e "${G}✓ devkitPro package set installed (or already satisfied)${RST}"
else
    echo -e "${G}✓ devkitPro toolchains already on disk${RST}"
fi

command -v arm-none-eabi-gcc &>/dev/null && echo -e "${G}✓ arm-none-eabi-gcc (GBA/NDS/3DS)${RST}"
command -v ee-gcc &>/dev/null && echo -e "${G}✓ PS2 (ee-gcc)${RST}"
command -v psp-gcc &>/dev/null && echo -e "${G}✓ PSP (psp-gcc)${RST}"
command -v ppu-gcc &>/dev/null && echo -e "${G}✓ PS3 (ppu-gcc)${RST}"

#-------------------------------------------------------------------------------
#  Nintendo 64  —  local tree only
#-------------------------------------------------------------------------------
echo -e "\n${C}== Nintendo 64 ==${RST}"
if command -v mips64-elf-gcc &>/dev/null; then
    echo -e "${G}✓ mips64-elf-gcc on PATH${RST}"
elif [[ -x ${HOME}/RetroSDKs/n64-toolchain/bin/mips64-elf-gcc ]]; then
    echo -e "${G}✓ ~/RetroSDKs/n64-toolchain/bin/mips64-elf-gcc${RST}"
else
    echo -e "${Y}Add mips64-elf toolchain under ~/RetroSDKs/n64-toolchain/${RST}"
fi

#-------------------------------------------------------------------------------
#  PS4 / PS5  —  local SDK roots only
#-------------------------------------------------------------------------------
echo -e "\n${C}== PS4 / PS5 (local SDK roots only) ==${RST}"
echo -e "${Y}Licensed SDKs only — not fetched by this script.${RST}"
echo -e "  ${C}PS4:${RST}  export ORBIS_SDK=\"\$HOME/RetroSDKs/ps4\""
echo -e "  ${C}PS5:${RST}  export PROSPERO_SDK=\"\$HOME/RetroSDKs/ps5\"  ${Y}(names per your vendor)${RST}"
mkdir -p "${HOME}/RetroSDKs/ps4" "${HOME}/RetroSDKs/ps5"
echo -e "${G}✓ ~/RetroSDKs/ps4 + ps5 ready${RST}"

#-------------------------------------------------------------------------------
#  PATH snippet (append once)
#-------------------------------------------------------------------------------
MARK="# --- AC TWEAKER 1.0 PATH ---"
if ! grep -Fq "${MARK}" "${HOME}/.bashrc" 2>/dev/null; then
    cat >>"${HOME}/.bashrc" <<EOF

${MARK} ${COPYRIGHT}
export PATH="\${HOME}/retro-dev/bin:\${PATH}"
export PATH="\${HOME}/RetroSDKs/gbdk/bin:\${PATH}"
export PATH="\${HOME}/RetroSDKs/n64-toolchain/bin:\${PATH}"
export DEVKITPRO=/opt/devkitpro
export PATH="\${DEVKITPRO}/tools/bin:\${DEVKITPRO}/devkitARM/bin:\${PATH}"
EOF
    echo -e "\n${G}Appended PATH block to ~/.bashrc${RST}"
fi

echo -e "\n${G}═══════════════════════════════════════════════════════════════${RST}"
echo -e "${G}  ${COPYRIGHT} — pass complete.${RST}"
echo -e "${G}═══════════════════════════════════════════════════════════════${RST}"
echo -e "${C}Reload:${RST}  source ~/.bashrc"
