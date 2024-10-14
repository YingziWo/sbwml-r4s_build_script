#!/bin/bash -e
set -x
pwd
ls -la
export RED_COLOR='\e[1;31m'
export GREEN_COLOR='\e[1;32m'
export YELLOW_COLOR='\e[1;33m'
export BLUE_COLOR='\e[1;34m'
export PINK_COLOR='\e[1;35m'
export SHAN='\e[1;33;5m'
export RES='\e[0m'

GROUP=
group() {
    endgroup
    echo "::group::  $1"
    GROUP=1
}
endgroup() {
    if [ -n "$GROUP" ]; then
        echo "::endgroup::"
    fi
    GROUP=
}

#####################################
#  NanoPi R4S OpenWrt Build Script  #
#####################################

# IP Location  #检测使用者IP所在地处在什么区域，下面具体的操作区分了两类，一类是CN的ip地址，一类为非CN的ip地址。根据ip区域提供不同的源目标位置。
ip_info=`curl -sk https://ip.cooluc.com`;
[ -n "$ip_info" ] && export isCN=`echo $ip_info | grep -Po 'country_code\":"\K[^"]+'` || export isCN=US

# script url   # 批命令网址
if [ "$isCN" = "CN" ]; then
    #export mirror=init.cooluc.com
    export mirror=raw.githubusercontent.com/YingziWo/sbwml-r4s_build_script/master
else
    #export mirror=init2.cooluc.com
    export mirror=raw.githubusercontent.com/YingziWo/sbwml-r4s_build_script/master
fi

# github actions - automatically retrieve `github raw` links   # 云编译项目版本选择master
if [ "$(whoami)" = "runner" ] && [ -n "$GITHUB_REPO" ]; then
    export mirror=raw.githubusercontent.com/$GITHUB_REPO/master
fi

# private gitea   #私有 gitea 网址
export gitea=git.cooluc.com

# github mirror   #判断云编译的工作区域引用不同的镜像网址，分为cn区域和非cn区域两块
if [ "$isCN" = "CN" ]; then
    export github="ghp.ci/github.com"
else
    export github="github.com"
fi

# Check root   #检查用户为非root用户继续执行，否则退出
if [ "$(id -u)" = "0" ]; then
    echo -e "${RED_COLOR}Building with root user is not supported.${RES}"
    exit 1
fi

# Start time   #确定开始云编译的日期和时间，并赋值
starttime=`date +'%Y-%m-%d %H:%M:%S'`
CURRENT_DATE=$(date +%s)

# Cpus     #检查云编译虚拟机的cpu核的数量，并赋值
cores=`expr $(nproc --all) + 1`

# $CURL_BAR   # 云编译的固件具体平台类型？
if curl --help | grep progress-bar >/dev/null 2>&1; then
    CURL_BAR="--progress-bar";
fi

if [ -z "$1" ] || [ "$2" != "nanopi-r4s" -a "$2" != "nanopi-r5s" -a "$2" != "x86_64" -a "$2" != "netgear_r8500" -a "$2" != "armv8" ]; then
    echo -e "\n${RED_COLOR}Building type not specified.${RES}\n"
    echo -e "Usage:\n"
    echo -e "nanopi-r4s releases: ${GREEN_COLOR}bash build.sh rc2 nanopi-r4s${RES}"
    echo -e "nanopi-r4s snapshots: ${GREEN_COLOR}bash build.sh dev nanopi-r4s${RES}"
    echo -e "nanopi-r5s releases: ${GREEN_COLOR}bash build.sh rc2 nanopi-r5s${RES}"
    echo -e "nanopi-r5s snapshots: ${GREEN_COLOR}bash build.sh dev nanopi-r5s${RES}"
    echo -e "x86_64 releases: ${GREEN_COLOR}bash build.sh rc2 x86_64${RES}"
    echo -e "x86_64 snapshots: ${GREEN_COLOR}bash build.sh dev x86_64${RES}"
    echo -e "netgear-r8500 releases: ${GREEN_COLOR}bash build.sh rc2 netgear_r8500${RES}"
    echo -e "netgear-r8500 snapshots: ${GREEN_COLOR}bash build.sh dev netgear_r8500${RES}"
    echo -e "armsr-armv8 releases: ${GREEN_COLOR}bash build.sh rc2 armv8${RES}"
    echo -e "armsr-armv8 snapshots: ${GREEN_COLOR}bash build.sh dev armv8${RES}\n"
    exit 1
fi

# Source branch   # 根据分支的不同选择源码的分支。dev选择openwrt-24.10，而rc2则选择openwrt-23.05的分支
if [ "$1" = "dev" ]; then
    export branch=master
    export version=snapshots-24.10
    export openwrt_version=openwrt-24.10
elif [ "$1" = "rc2" ]; then
    latest_release="v$(curl -s https://$mirror/tags/v23)"
    export branch=$latest_release
    export version=rc2
    export openwrt_version=openwrt-23.05
fi

# lan     #固件的lan口ip地址定义
[ -n "$LAN" ] && export LAN=$LAN || export LAN=10.0.0.1

# platform  #用户所选择的硬件平台所对应的.config参数toolchain_arch的赋值
[ "$2" = "armv8" ] && export platform="armv8" toolchain_arch="aarch64_generic"
[ "$2" = "nanopi-r4s" ] && export platform="rk3399" toolchain_arch="aarch64_generic"
[ "$2" = "nanopi-r5s" ] && export platform="rk3568" toolchain_arch="aarch64_generic"
[ "$2" = "netgear_r8500" ] && export platform="bcm53xx" toolchain_arch="arm_cortex-a9"
[ "$2" = "x86_64" ] && export platform="x86_64" toolchain_arch="x86_64"

# gcc13 & 14 & 15  # 三种编译器版本gcc_version的赋值选择
if [ "$USE_GCC13" = y ]; then
    export USE_GCC13=y gcc_version=13
    # use mold
    [ "$ENABLE_MOLD" = y ] && export ENABLE_MOLD=y
elif [ "$USE_GCC14" = y ]; then
    export USE_GCC14=y gcc_version=14
    # use mold
    [ "$ENABLE_MOLD" = y ] && export ENABLE_MOLD=y
elif [ "$USE_GCC15" = y ]; then
    export USE_GCC15=y gcc_version=15
    # use mold
    [ "$ENABLE_MOLD" = y ] && export ENABLE_MOLD=y
else
    export gcc_version=11
fi

# build.sh flags    #批命令build.sh的变量参数展示
export \
    ENABLE_BPF=$ENABLE_BPF \
    ENABLE_DPDK=$ENABLE_DPDK \
    ENABLE_GLIBC=$ENABLE_GLIBC \
    ENABLE_LRNG=$ENABLE_LRNG \
    KERNEL_CLANG_LTO=$KERNEL_CLANG_LTO \
    TESTING_KERNEL=$TESTING_KERNEL \

# kernel version    # 若变量参数TESTING_KERNEL的值是“y”,linux内核版本选6.12，不然选6.6版本
[ "$TESTING_KERNEL" = "y" ] && export kernel_version=6.12 || export kernel_version=6.6

# print version
echo -e "\r\n${GREEN_COLOR}Building $branch${RES}\r\n"
if [ "$platform" = "x86_64" ]; then
    echo -e "${GREEN_COLOR}Model: x86_64${RES}"
elif [ "$platform" = "armv8" ]; then
    echo -e "${GREEN_COLOR}Model: armsr/armv8${RES}"
    [ "$1" = "rc2" ] && model="armv8"
elif [ "$platform" = "bcm53xx" ]; then
    echo -e "${GREEN_COLOR}Model: netgear_r8500${RES}"
    [ "$LAN" = "10.0.0.1" ] && export LAN="192.168.1.1"
elif [ "$platform" = "rk3568" ]; then
    echo -e "${GREEN_COLOR}Model: nanopi-r5s/r5c${RES}"
    [ "$1" = "rc2" ] && model="nanopi-r5s"
else
    echo -e "${GREEN_COLOR}Model: nanopi-r4s${RES}"
    [ "$1" = "rc2" ] && model="nanopi-r4s"
fi
get_kernel_version=$(curl -s https://$mirror/tags/kernel-$kernel_version)
kmod_hash=$(echo -e "$get_kernel_version" | awk -F'HASH-' '{print $2}' | awk '{print $1}' | tail -1 | md5sum | awk '{print $1}')
if [ "$TESTING_KERNEL" = "y" ]; then
    kmodpkg_name=$(echo $(echo -e "$get_kernel_version" | awk -F'HASH-' '{print $2}' | awk '{print $1}')~$(echo $kmod_hash)-r1)
else
    kmodpkg_name=$(echo $(echo -e "$get_kernel_version" | awk -F'HASH-' '{print $2}' | awk '{print $1}')-1-$(echo $kmod_hash))
fi
echo -e "${GREEN_COLOR}Kernel: $kmodpkg_name ${RES}"

echo -e "${GREEN_COLOR}Date: $CURRENT_DATE${RES}\r\n"
echo -e "${GREEN_COLOR}GCC VERSION: $gcc_version${RES}"
[ -n "$LAN" ] && echo -e "${GREEN_COLOR}LAN: $LAN${RES}" || echo -e "${GREEN_COLOR}LAN: 10.0.0.1${RES}"
[ "$ENABLE_GLIBC" = "y" ] && echo -e "${GREEN_COLOR}Standard C Library:${RES} ${BLUE_COLOR}glibc${RES}" || echo -e "${GREEN_COLOR}Standard C Library:${RES} ${BLUE_COLOR}musl${RES}"
[ "$ENABLE_OTA" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_OTA: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_OTA:${RES} ${YELLOW_COLOR}false${RES}"
[ "$ENABLE_DPDK" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_DPDK: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_DPDK:${RES} ${YELLOW_COLOR}false${RES}"
[ "$ENABLE_MOLD" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_MOLD: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_MOLD:${RES} ${YELLOW_COLOR}false${RES}"
[ "$ENABLE_BPF" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_BPF: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_BPF:${RES} ${RED_COLOR}false${RES}"
[ "$ENABLE_LTO" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_LTO: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_LTO:${RES} ${RED_COLOR}false${RES}"
[ "$ENABLE_LRNG" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_LRNG: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_LRNG:${RES} ${RED_COLOR}false${RES}"
[ "$ENABLE_LOCAL_KMOD" = "y" ] && echo -e "${GREEN_COLOR}ENABLE_LOCAL_KMOD: true${RES}" || echo -e "${GREEN_COLOR}ENABLE_LOCAL_KMOD: false${RES}"
[ "$BUILD_FAST" = "y" ] && echo -e "${GREEN_COLOR}BUILD_FAST: true${RES}" || echo -e "${GREEN_COLOR}BUILD_FAST:${RES} ${YELLOW_COLOR}false${RES}"
[ "$MINIMAL_BUILD" = "y" ] && echo -e "${GREEN_COLOR}MINIMAL_BUILD: true${RES}" || echo -e "${GREEN_COLOR}MINIMAL_BUILD: false${RES}"
[ "$KERNEL_CLANG_LTO" = "y" ] && echo -e "${GREEN_COLOR}KERNEL_CLANG_LTO: true${RES}\r\n" || echo -e "${GREEN_COLOR}KERNEL_CLANG_LTO:${RES} ${YELLOW_COLOR}false${RES}\r\n"

# clean old files  #清除可能存在的旧目录和旧目录中的文件，删整个临时目录openwrt和 master两个可能存在的目录
rm -rf openwrt master

# openwrt - releases  # 所有硬件平台缺省用的原码，dev用master分支，rc2用23.05.5分支，并克隆的同时建立了openwrt的目录
[ "$(whoami)" = "runner" ] && group "source code"
git clone --depth=1 https://$github/openwrt/openwrt -b $branch

# openwrt master   #根据硬件平台的不同，若是rc2，则再克隆下面四个目录，同时建立了master目录和master下的四个分目录
if [ "$1" = "rc2" ]; then
    git clone https://$github/openwrt/openwrt master/openwrt --depth=1
    git clone https://$github/openwrt/packages master/packages --depth=1
    git clone https://$github/openwrt/luci master/luci --depth=1
    git clone https://$github/openwrt/routing master/routing --depth=1
fi

# openwrt-23.05    # 硬件平台是rc2，则在克隆一个openwrt-23.05的分支到master/openwrt-23.05中
[ "$1" = "rc2" ] && git clone https://$github/openwrt/openwrt -b openwrt-23.05 master/openwrt-23.05 --depth=1

# immortalwrt master  #不同平台必须选的源码包，作为上面原码的补充，以更好地适合不同插件的应用 ，若有openwrt的目录，则硬件平台rc2给version.date赋值日期，给编译文件include/version.mk改版本号，再释放key.tar.gz压缩包，再删该文件。若无openwrt目录，下载原码失败，退出云编译。
git clone https://$github/immortalwrt/packages master/immortalwrt_packages --depth=1
[ "$(whoami)" = "runner" ] && endgroup

if [ -d openwrt ]; then
    cd openwrt
    [ "$1" = "rc2" ] && echo "$CURRENT_DATE" > version.date
    [ "$1" = "dev" ] && sed -i 's/$(VERSION_NUMBER),SNAPSHOT/$(VERSION_NUMBER),24.10-SNAPSHOT/g' include/version.mk
    curl -Os https://$mirror/openwrt/patch/key.tar.gz && tar zxf key.tar.gz && rm -f key.tar.gz
else
    echo -e "${RED_COLOR}Failed to download source code${RES}"
    exit 1
fi

# tags
if [ "$1" = "rc2" ]; then
    git describe --abbrev=0 --tags > version.txt
else
    git branch | awk '{print $2}' > version.txt
fi

# feeds mirror
if [ "$1" = "rc2" ]; then
    packages="^$(grep packages feeds.conf.default | awk -F^ '{print $2}')"
    luci="^$(grep luci feeds.conf.default | awk -F^ '{print $2}')"
    routing="^$(grep routing feeds.conf.default | awk -F^ '{print $2}')"
    telephony="^$(grep telephony feeds.conf.default | awk -F^ '{print $2}')"
else
    packages=";$branch"
    luci=";$branch"
    routing=";$branch"
    telephony=";$branch"
fi
cat > feeds.conf <<EOF
src-git packages https://$github/openwrt/packages.git$packages
src-git luci https://$github/openwrt/luci.git$luci
src-git routing https://$github/openwrt/routing.git$routing
src-git telephony https://$github/openwrt/telephony.git$telephony
EOF

# Init feeds
[ "$(whoami)" = "runner" ] && group "feeds update -a"
./scripts/feeds update -a
[ "$(whoami)" = "runner" ] && endgroup

[ "$(whoami)" = "runner" ] && group "feeds install -a"
./scripts/feeds install -a
[ "$(whoami)" = "runner" ] && endgroup

# loader dl
if [ -f ../dl.gz ]; then
    tar xf ../dl.gz -C .
fi

###############################################
echo -e "\n${GREEN_COLOR}Patching ...${RES}\n"

# scripts
curl -sO https://$mirror/openwrt/scripts/00-prepare_base.sh
curl -sO https://$mirror/openwrt/scripts/01-prepare_base-mainline.sh
curl -sO https://$mirror/openwrt/scripts/02-prepare_package.sh
curl -sO https://$mirror/openwrt/scripts/03-convert_translation.sh
curl -sO https://$mirror/openwrt/scripts/04-fix_kmod.sh
curl -sO https://$mirror/openwrt/scripts/05-fix-source.sh
curl -sO https://$mirror/openwrt/scripts/99_clean_build_cache.sh
if [ -n "$git_password" ] && [ -n "$private_url" ]; then
    curl -u openwrt:$git_password -sO "$private_url"
else
    curl -sO https://$mirror/openwrt/scripts/10-custom.sh
fi
chmod 0755 *sh
[ "$(whoami)" = "runner" ] && group "patching openwrt"
bash 00-prepare_base.sh
bash 01-prepare_base-mainline.sh
bash 02-prepare_package.sh
bash 03-convert_translation.sh
bash 04-fix_kmod.sh
bash 05-fix-source.sh
[ -f "10-custom.sh" ] && bash 10-custom.sh
[ "$(whoami)" = "runner" ] && endgroup

if [ "$USE_GCC14" = "y" ] || [ "$USE_GCC15" = "y" ] && [ "$version" = "rc2" ]; then
    rm -rf toolchain/binutils
    cp -a ../master/openwrt/toolchain/binutils toolchain/binutils
fi

pwd
ls -a



# 很少有人会告诉你为什么要这样做，而是会要求你必须要这样做。
