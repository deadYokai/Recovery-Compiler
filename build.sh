#!/bin/bash

printf "\e[1;32m \u2730 Recovery Compiler\e[0m\n\n"

echo "::group::Free Space Checkup"
if [[ ! $(df / --output=avail | tail -1 | awk '{print $NF}') -ge 41943040 ]]; then
    printf "Please use 'slimhub_actions@main' Action prior to this Recovery Compiler Action to gain at least 40 GB space\n"
    exit 1
else
    printf "You have %s space available\n" "$(df -h / --output=avail | tail -1 | awk '{print $NF}')"
fi
echo "::endgroup::"

echo "::group::Mandatory Variables Checkup"

if [[ -z ${VENDOR} || -z ${CODENAME} ]]; then
    # Assume the workflow runs in the device tree
    # And the naming is exactly like android_device_vendor_codename(_split_codename)(-pbrp)
    # Optimized for PBRP Device Trees
	VenCode=$(echo ${GITHUB_REPOSITORY#*/} | sed 's/android_device_//;s/-pbrp//;s/-recovery//')
    export VENDOR=$(echo ${VenCode} | cut -d'_' -f1)
    export CODENAME=$(echo ${VenCode} | cut -d'_' -f2-)
	unset VenCode
fi
if [[ -z ${DT_LINK} ]]; then
    # Assume the workflow runs in the device tree with the current checked-out branch
    DT_BR=${GITHUB_REF##*/}
    export DT_LINK="https://github.com/${GITHUB_REPOSITORY} -b ${DT_BR}"
	unset DT_BR
fi
# Default TARGET will be recoveryimage if not provided
export TARGET=${TARGET:-recoveryimage}
# Default FLAVOR will be eng if not provided
export FLAVOR=${FLAVOR:-eng}
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
    lsb-core lsb-security patchutils bc \
    android-sdk-platform-tools adb fastboot \
    openjdk-8-jdk ca-certificates-java maven \
    python3-all-dev python-is-python3 python2 \
    lzip lzop xzdec pixz libzstd-dev lib32z1-dev \
    exfatprogs exfat-fuse \
    build-essential gcc gcc-multilib g++-multilib clang llvm lld cmake ninja-build \
    libxml2-utils xsltproc expat re2c libxml2-utils xsltproc expat re2c \
    libreadline-dev libsdl1.2-dev libtinfo5 xterm rename schedtool bison gperf libb2-dev \
    pngcrush imagemagick optipng advancecomp ccache wget
printf "Cleaning Some Programs...\n"
sudo apt-get -qqy purge default-jre-headless openjdk-11-jre-headless python &>/dev/null
sudo apt-get -qy clean &>/dev/null && sudo apt-get -qy autoremove &>/dev/null
sudo rm -rf -- /var/lib/apt/lists/* /var/cache/apt/archives/* &>/dev/null
echo "::endgroup::"

echo "::group::Installation Of repo"
cd /home/runner || exit 1
printf "Adding latest stable repo...\n"
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
. /home/runner/.bashrc 2>/dev/null
echo "::endgroup::"

echo "::group::Setting ccache"
mkdir -p /opt/ccache &>/dev/null
sudo chown runner:docker /opt/ccache
CCACHE_DIR=/opt/ccache ccache -M 5G &>/dev/null
printf "All Preparation Done.\nReady To Build Recoveries...\n"
echo "::endgroup::"

echo "::group::Source Repo Sync"
printf "Initializing Repo\n"
python --version
python3 --version
python2 --version
printf "Getting OrangeFox manifest (this can take up to 1 hour, and can use up to 40GB of disk space)"
mkdir ~/fox_10.0
cd ~/fox_10.0
wget https://gitlab.com/OrangeFox/sync/-/raw/master/legacy/orangefox_sync_legacy.sh
wget https://gitlab.com/OrangeFox/sync/-/raw/master/legacy/build_fox.sh
chmod +x orangefox_sync_legacy.sh
chmod +x build_fox.sh
mkdir patches
wget -O patches/patch-manifest-fox_10.0.diff https://gitlab.com/OrangeFox/sync/-/raw/master/patches/patch-manifest-fox_10.0.diff
./orangefox_sync_legacy.sh --branch 10.0 --path ~/fox_10.0 || { printf "Compilation failed.\n"; exit 1; }
echo "::endgroup::"

echo "::group::Device and Kernel Tree Cloning"
printf "Cloning Device Tree\n"
cd ~/fox_10.0
if [[ ! -z "${VENDOR_REPO}" ]]; then
    printf "Using Vendor Repo\n"
    git clone ${VENDOR_REPO} --depth=1 vendor/${VENDOR}/${CODENAME}
fi
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
    cd /home/runner/fox_10.0 || exit
fi
echo "::endgroup::"

echo "::group::Compilation"
export ALLOW_MISSING_DEPENDENCIES=true

# Only for (Unofficial) TWRP Building...
# If lunch throws error for roomservice, saying like `device tree not found` or `fetching device already present`,
# replace the `roomservice.py` with appropriate one according to platform version from here
# >> https://gist.github.com/rokibhasansagar/247ddd4ef00dcc9d3340397322051e6a/
# and then `source` and `lunch` again

cd ~/fox_10.0
./build_fox.sh ${CODENAME} || { printf "Compilation failed.\n"; exit 1; }
echo "::endgroup::"

# Export VENDOR, CODENAME and BuildPath for next steps
echo "VENDOR=${VENDOR}" >> ${GITHUB_ENV}
echo "CODENAME=${CODENAME}" >> ${GITHUB_ENV}
echo "BuildPath=/home/runner/fox_10.0" >> ${GITHUB_ENV}

# TODO:: Add GitHub Release Script Here
