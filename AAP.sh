#!/bin/bash
#by Akina | LuoYan
#2024-06-03 Rewrite
#shellcheck disable=SC2059,SC2086,SC2166

if [ -n "${APTOOLDEBUG}" ]; then
    if [ ${APTOOLDEBUG} -eq 1 ]; then
        printf "[\033[1;33m[WARN] $(date "+%H:%M:%S"): Debug mode is on.\033[0m\n"
        set -x
    fi
fi
# 特殊变量
RED="\033[1;31m"    # RED
YELLOW="\033[1;33m" # YELLOW
BLUE="\033[40;34m"  # BLUE
RESET="\033[0m"     # RESET

# 格式化打印消息
msg_info() { # 打印消息 格式: "[INFO] TIME: MSG"(BLUE)
    printf "${BLUE}[INFO] $(date "+%H:%M:%S"): ${1}${RESET}\n"
}
msg_warn() { # 打印消息 格式: "[WARN] TIME: MSG"(YELLOW)
    printf "${YELLOW}[WARN] $(date "+%H:%M:%S"): ${1}${RESET}\n"
}
msg_err() { # 打印消息 格式: "[ERROR] TIME: MSG"(RED)
    printf "${RED}[ERROR] $(date "+%H:%M:%S"): ${1}${RESET}\n"
}
msg_fatal() { # 打印消息 格式: "[FATAL] TIME: MSG"(RED)
    printf "${RED}[FATAL] $(date "+%H:%M:%S"): ${1}${RESET}\n"
}
# OS 检测
if command -v getprop >/dev/null 2>&1; then
    OS="android"
else
    OS="linux"
fi
# ROOT 检测
if [ "$(id -u)" -eq 0 ]; then
    ROOT=true
    if [ "${OS}" = "android" ]; then
        if [ "$(magisk -v | grep "delta")" -o "$(magisk -v | grep "kitsune")" ]; then
            msg_fatal "Detected Magisk Deleta/Kitsune: Unsupported environment. Aborted."
            exit 114
        fi
    fi
else
    ROOT=false
    msg_warn "You are running in unprivileged mode; some functionality may be limited."
fi

if [ -z "$(echo ${PREFIX} | grep -i termux)" -a "${OS}" = "android" ]; then
    msg_warn "Unsupported terminal app(not in Termux)."
fi
print_help() {
    printf "${BLUE}%s${RESET}\n\n" "
APatch Auto Patch Tool
Written by Akina
Version: 7.0.0
Current DIR: $(pwd)

-h, -v,                 print the usage and version.
-i PATH/TO/IMAGE,       specify a boot image path.
-k [RELEASE NAME],      specify a kernelpatch version [RELEASE NAME].
-d PATH/TO/DIR,         specify a folder containing AAPFunction, kptools and kpimg that we need.
-s \"STRING\",            specify a superkey. Use STRING as superkey.
-K,                     Specify the KPMs to be embedded.
-I,                     directly install to current slot after patch.
-S,                     Install to another slot (for OTA).
-E [ARGS],              Add args [ARGS] to kptools when patching.
-c [COMMANDS],          Specifies extra commands to run (developers only)."
    TWIDTH=$(tput cols)
    TEXTLEN=${#text}
    MIDPOS=$(((TWIDTH - TEXTLEN) / 2))
    printf "${BLUE}%*s${RESET}\n" $MIDPOS "NOTE"
    printf "${BLUE}%s${RESET}\n" "When arg -I is not specified, the patched boot image will be stored in /storage/emulated/0/patched_boot.img(on android) or \${HOME}/patched_boot.img(on linux).

When the -s parameter is not specified, uuid will be used to generate an 8-digit SuperKey that is a mixture of alphanumeric characters.

When the -d parameter is specified, the specified folder should contain AAPFunction, magiskboot, kptools and kpimg, otherwise you will get a fatal error.

In addition, you can use \`APTOOLDEBUG=1 ${0} [ARGS]\` format to enter verbose mode.
"
    exit 0
}

# 参数解析
DOWNFILES=true
while getopts ":hvi:k:KIVs:Sd:E:c:" OPT; do
    # $OPTARG
    case $OPT in
    c)
        bash -c "$OPTARG"
        ;;
    h | v)
        print_help
        ;;
    d)
        MISSINGFILES=0
        WORKDIR="$(realpath ${OPTARG})"
        if [ ! -d "${WORKDIR}" ]; then
            msg_fatal "No such directory."
            exit 1
        fi
        for i in AAPFunction magiskboot kptools-${OS} kpimg-android; do
            if [ ! -e "${WORKDIR}/${i}" ]; then
                msg_fatal "Missing file: ${WORKDIR}/${i}"
                MISSINGFILES=$((MISSINGFILES + 1))
            fi
        done
        if [[ ${MISSINGFILES} -gt 0 ]]; then
            msg_fatal "There are ${MISSINGFILES} files missing, and we need 4 files in total. Please read the instructions in ${0} -h."
            msg_info "Omit the -d parameter; the file will be downloaded remotely."
        else
            msg_info "The work directory was manually specified: ${WORKDIR}. AAPFunction, kptools and kpimg will not be downloaded again."
            DOWNFILES=false
        fi
        ;;
    K)
        EMBEDKPMS=true
        msg_info "The -K parameter was received. Will embed KPMs."
        ;;
    i)
        BOOTPATH="$(realpath ${OPTARG})"
        if [ -e "${BOOTPATH}" ]; then
            msg_info "Boot image path specified. Current image path: ${BOOTPATH}"
            if [ ! -f "${BOOTPATH}" ]; then
                msg_fatal "${BOOTPATH}: Not a file."
                exit 1
            fi
        else
            msg_fatal "${BOOTPATH}: The file does not exist."
            exit 1
        fi
        ;;
    S)
        SAVEROOT="true"
        msg_info "The -S parameter was received. The patched image will be flashed into another slot if this is a ab partition device."
        ;;
    I)
        if [ "${OS}" = "android" ]; then
            INSTALL="true"
            msg_info "The -I parameter was received. Will install after patching."
        else
            msg_fatal "Do not use this arg without Android!"
            exit 1
        fi
        ;;
    s)
        SUPERKEY="${OPTARG}"
        msg_info "The -s parameter was received. Currently specified SuperKey: ${SUPERKEY}."
        ;;
    k)
        KPTOOLVER="${OPTARG}"
        msg_info "The -k parameter was received. Will use kptool ${KPTOOLVER}."
        ;;
    E)
        EXTRAARGS="${OPTARG}"
        msg_info "The -E parameter was received. Current extra args: ${EXTRAARGS}"
        ;;
    :)
        msg_fatal "Option -${OPTARG} requires an argument.." >&2
        exit 1
        ;;

    ?)
        msg_fatal "Invalid option: -${OPTARG}" >&2
        exit 1
        ;;
    esac
done
# 镜像路径检测(For Linux)
if [ "${OS}" = "linux" -a -z "${BOOTPATH}" ]; then
    msg_fatal "You are using ${OS}, but there is no image specified by you. Aborted."
    exit 1
fi
if [ -e "${BOOTPATH}" -a ! -f "${BOOTPATH}" ]; then
    msg_fatal "You specified a path, but that path is not a file!"
    exit 1
fi
# 无 ROOT 并且未指定 BOOT 镜像路径则退出
if [ -z "${BOOTPATH}" -a "${ROOT}" = "false" ]; then
    msg_fatal "No root and no boot image is specified. Aborted."
    exit 1
fi
# 设置工作文件夹
if [ -z "${WORKDIR}" ]; then
    WORKDIR="$(mktemp -d)"
fi
# 判断用户设备是否为ab分区，是则设置$BOOTSUFFIX
if [ "${OS}" = "android" ]; then
    BYNAMEPATH=$(getprop ro.frp.pst | sed 's/\/frp//g')
    if [ ! -e "${BYNAMEPATH}/boot" ]; then
        BOOTSUFFIX=$(getprop ro.boot.slot_suffix)
    fi
else
    msg_info "Current OS is not Android. Skip boot slot check."
fi
# 判断OTA保root应使用的槽位
if [ -n "${SAVEROOT}" -a -n "${BOOTSUFFIX}" -a "${OS}" = "android" ]; then
    if [ "${BOOTSUFFIX}" = "_a" ]; then
        TBOOTSUFFIX="_b"
    else
        TBOOTSUFFIX="_a"
    fi
    msg_warn "You have specified the installation to another slot. Current slot:${BOOTSUFFIX}. Slot to be flashed into:${TBOOTSUFFIX}."
fi
# 未指定superkey则使用uuid生成
if [ -z "${SUPERKEY}" ]; then
    SUPERKEY="$(cat /proc/sys/kernel/random/uuid | cut -d \- -f1)"
fi

if [[ "${DOWNFILES}" == "true" ]]; then
    msg_info "Downloading function file from GitHub..."
    curl -L --progress-bar "https://raw.githubusercontent.com/AkinaAcct/APatchTool/main/AAPFunction" -o ${WORKDIR}/AAPFunction
    EXITSTATUS=$?
    if [ $EXITSTATUS != 0 ]; then
        msg_fatal "Download failed. Check your Internet connection and try again."
        exit 1
    fi
fi

# 备份boot
msg_info "Now backing up the boot image..."
if [ "${ROOT}" == "true" ]; then
    if [ "${OS}" == "android" ]; then
        msg_info "Backing up boot image..."
        dd if=${BYNAMEPATH}/boot${BOOTSUFFIX} of=/storage/emulated/0/stock_boot${BOOTSUFFIX}.img
        EXITSTATUS=$?
        if [ "${EXITSTATUS}" != "0" ]; then
            msg_err "Boot image backup failed."
            msg_warn "Skip backing up boot image..."
        else
            msg_info "Done. Boot image path: /storage/emulated/0/stock_boot${BOOTSUFFIX}.img"
        fi
    else
        msg_info "Currently OS in not Android; Skip backup."
    fi
else
    msg_warn "No root. Skip back up."
fi

# 加载操作文件
. ${WORKDIR}/AAPFunction

get_device_boot
get_tools
patch_boot
if [ -n "${INSTALL}" ]; then
    msg_warn "The -I parameter was received. Will install patched image."
    flash_boot
else
    if [ "${OS}" = "android" ]; then
        msg_info "Now copying patched image to /storage/emulated/0/patched_boot.img..."
        mv ${WORKDIR}/new-boot.img /storage/emulated/0/patched_boot.img
    else
        msg_info "Now copying patched image to ${HOME}/patched_boot.img..."
        mv ${WORKDIR}/new-boot.img "${HOME}/patched_boot.img"
    fi
    msg_info "Done. Now deleting tmp files..."
    rm -rf ${WORKDIR}
    msg_info "Done."
fi
print_superkey
