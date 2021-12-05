#!/bin/bash

printf "\e[1;32m Recovery Compiler\e[0m\n\n"

echo "::group::Free Space Checkup"
if [[ ! $(df / --output=avail | tail -1 | awk '{print $NF}') -ge 41943040 ]]; then
    printf "Please use 'slimhub_actions@main' Action prior to this Recovery Compiler Action to gain at least 40 GB space\n"
    exit 1
else
    printf "You have %s space available\n" "$(df -h / --output=avail | tail -1 | awk '{print $NF}')"
fi
echo "::endgroup::"

echo "::group::Mandatory Variables Checkup"
if [[ -z ${MANIFEST} ]]; then
    printf "Please Provide A Manifest URL with/without Branch\n"
    exit 1
fi
if [[ -z ${VENDOR} || -z ${CODENAME} ]]; then
    export VENDOR=oukitel
    export CODENAME=c18pro
fi
if [[ -z ${DT_LINK} ]]; then
    export DT_LINK="https://github.com/OneGameKoTT/android_device_${VENDOR}_${CODENAME}-pbrp -b android-10.0"
	unset DT_BR
fi
# Default TARGET will be recoveryimage if not provided
export TARGET=${TARGET:-recoveryimage}
# Default FLAVOR will be eng if not provided
export FLAVOR=${FLAVOR:-userdebug}
# Default TZ (Timezone) will be set as UTC if not provided
export TZ=${TZ:-UTC}
if [[ ! ${TZ} == "UTC" ]]; then
    sudo timedatectl set-timezone ${TZ}
fi
echo "::endgroup::"

printf "We are going to build ${FLAVOR}-flavored ${TARGET} for ${CODENAME} from the manufacturer ${VENDOR}\n"

echo "::group::Installation Of Recommended Programs"
export \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    JAVA_OPTS=" -Xmx7G " JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
sudo apt-get -qqy update &>/dev/null
sudo apt-get -qqy install --no-install-recommends \
    ubuntu-minimal lsb-core lsb-security patchutils bc \
    android-sdk-platform-tools adb fastboot \
    openjdk-8-jdk ca-certificates-java maven \
    python3.8 python3-pip python3-all-dev python-is-python3 python2 \
    lzip lzop xzdec pixz libzstd-dev lib32z1-dev \
    exfat-utils exfat-fuse \
    build-essential gcc gcc-multilib g++-multilib clang llvm lld cmake ninja-build \
    libxml2-utils xsltproc expat re2c libxml2-utils xsltproc expat re2c \
    libreadline-gplv2-dev libsdl1.2-dev libtinfo5 xterm rename schedtool bison gperf libb2-dev \
    pngcrush imagemagick optipng advancecomp ccache &>/dev/null
printf "Cleaning Some Programs...\n"
sudo apt-get -qqy purge default-jre-headless openjdk-11-jre-headless python &>/dev/null
sudo apt-get -qy clean &>/dev/null && sudo apt-get -qy autoremove &>/dev/null
sudo rm -rf -- /var/lib/apt/lists/* /var/cache/apt/archives/* &>/dev/null
#Force link python3
[ -e /usr/bin/python ] && sudo rm -- /usr/bin/python
sudo ln -s /usr/bin/python3 /usr/bin/python &>/dev/null
[ -e /usr/bin/pip ] && sudo rm -- /usr/bin/pip
sudo ln -s /usr/bin/pip3 /usr/bin/pip &>/dev/null
echo "::endgroup::"

echo "::group::Installation Of git-repo"
cd ~|| exit 1
printf "Adding latest stable git-repo binary...\n"
curl -sL https://storage.googleapis.com/git-repo-downloads/repo > repo
chmod a+rx ./repo && sudo mv ./repo /usr/local/bin/
echo "::endgroup::"

echo "::group::Doing Some Random Stuff"
if [ -e /lib/x86_64-linux-gnu/libncurses.so.6 ] && [ ! -e /usr/lib/x86_64-linux-gnu/libncurses.so.5 ]; then
    ln -s /lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
fi
export \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    USE_CCACHE=1 CCACHE_COMPRESS=1 CCACHE_COMPRESSLEVEL=8 CCACHE_DIR=/opt/ccache \
    TERM=xterm-256color
. ~/.bashrc 2>/dev/null
echo "::endgroup::"

echo "::group::Setting ccache"
mkdir -p /opt/ccache &>/dev/null
#sudo chown $(whoami):docker /opt/ccache
CCACHE_DIR=/opt/ccache ccache -M 5G &>/dev/null
printf "All Preparation Done.\nReady To Build Recoveries...\n"
echo "::endgroup::"

# cd To An Absolute Path
mkdir -p ~/builder &>/dev/null
cd ~/builder || exit 1

echo "::group::Source Repo Sync"
printf "Initializing Repo\n"
python --version
python3 --version
printf "We will be using %s for Manifest source\n" "${MANIFEST}"
repo --color=always init -q -u ${MANIFEST} --depth=1 --groups=all,-notdefault,-device,-darwin,-x86,-mips || { printf "Repo Initialization Failed.\n"; exit 1; }
repo --color=always sync -c -q --force-sync --no-clone-bundle --no-tags -j6 || { printf "Git-Repo Sync Failed.\n"; exit 1; }
echo "::endgroup::"

echo "::group::Device and Kernel Tree Cloning"
printf "Cloning Device Tree\n"
git clone ${DT_LINK} --depth=1 device/${VENDOR}/${CODENAME}
# omni.dependencies file is a must inside DT, otherwise lunch fails
[[ ! -f device/${VENDOR}/${CODENAME}/omni.dependencies ]] && printf "[\n]\n" > device/${VENDOR}/${CODENAME}/omni.dependencies
if [[ ! -z "${KERNEL_LINK}" ]]; then
    printf "Using Manual Kernel Compilation\n"
    git clone ${KERNEL_LINK} --depth=1 kernel/${VENDOR}/${CODENAME}
else
    printf "Using Prebuilt Kernel For The Build.\n"
fi
echo "::endgroup::"

echo "::group::Extra Commands"
if [[ ! -z "$EXTRA_CMD" ]]; then
    printf "Executing Extra Commands\n"
    eval "${EXTRA_CMD}"
    cd ~/builder 
fi
echo "::endgroup::"

echo "::group::Pre-Compilation"
printf "Compiling Recovery...\n"
export ALLOW_MISSING_DEPENDENCIES=true

source build/envsetup.sh
lunch omni_${CODENAME}-${FLAVOR} || { printf "Compilation failed.\n"; exit 1; }
echo "::endgroup::"

echo "::group::Compilation"
#mka ${TARGET} || { printf "Compilation failed.\n"; exit 1; }
make -j1 ${TARGET} || { printf "Compilation failed.\n"; exit 1; }
echo "::endgroup::"

# Export VENDOR, CODENAME and BuildPath for next steps
export "VENDOR=${VENDOR}"
export "CODENAME=${CODENAME}"
export "BuildPath=~/builder"

# TODO:: Add GitHub Release Script Here
