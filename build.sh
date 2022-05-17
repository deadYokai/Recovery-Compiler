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
if [[ -z ${MANIFEST} ]]; then
    printf "Please Provide A Manifest URL with/without Branch\n"
    exit 1
fi
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

echo "::group::Configuration"
export \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    JAVA_OPTS=" -Xmx7G " JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
echo '[multilib]' | sudo tee -a /etc/pacman.conf
echo 'Include = /etc/pacman.d/mirrorlist' | sudo tee -a /etc/pacman.conf
sudo sed -i 's/^SigLevel/#SigLevel/' /etc/pacman.conf
sudo sed -i 's/\[options\]/\[options\]\nSigLevel = Never/' /etc/pacman.conf


# sudo tee /etc/pacman.d/mirrorlist &>/dev/null << EOF
# ##
# ## Arch Linux repository mirrorlist
# ## Filtered by mirror score from mirror status page
# ## Generated on 2022-04-13
# ##

# ## Ukraine
# Server = http://mirror.mirohost.net/archlinux/$repo/os/$arch
# ## Ukraine
# Server = http://repo.endpoint.ml/archlinux/$repo/os/$arch
# ## Ukraine
# Server = https://repo.endpoint.ml/archlinux/$repo/os/$arch
# ## Ukraine
# Server = https://mirrors.nix.org.ua/linux/archlinux/$repo/os/$arch
# ## Ukraine
# Server = http://archlinux.astra.in.ua/$repo/os/$arch
# ## Ukraine
# Server = https://archlinux.astra.in.ua/$repo/os/$arch
# ## Ukraine
# Server = https://archlinux.ip-connect.vn.ua/$repo/os/$arch
# ## Ukraine
# Server = http://mirrors.nix.org.ua/linux/archlinux/$repo/os/$arch
# ## Ukraine
# Server = https://mirror.mirohost.net/archlinux/$repo/os/$arch
# ## Ukraine
# Server = http://archlinux.ip-connect.vn.ua/$repo/os/$arch
# EOF

# # cat /etc/pacman.conf
# printf ";;;;"
cat /etc/pacman.d/mirrorlist
sudo pacman --noconfirm -Syy archlinux-keyring
echo "::endgroup::"

echo "::group::Instaaalimg"
sudo pacman --noconfirm -S lib32-gcc-libs git wget repo gnupg flex \
 bison gperf sdl wxgtk2 squashfs-tools curl ncurses zlib \
 schedtool perl-switch zip unzip libxslt \
 bc rsync lib32-zlib lib32-ncurses lib32-readline clang \
 compiler-rt clazy lib32-clang lib32-clang llvm cpio python python2 ccache \
 jre8-openjdk-headless jre8-openjdk jdk8-openjdk openjdk8-doc openjdk8-src
printf "Installing yay...\n"
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
cd .. && rm -rf yay-bin
yay --noconfirm -S lib32-ncurses5-compat-libs ncurses5-compat-libs
printf "Cleaning Cache...\n"
yay --noconfirm -Scc &>/dev/null
printf "You have %s space available\n" "$(df -h / --output=avail | tail -1 | awk '{print $NF}')"
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

# cd To An Absolute Path
mkdir -p /home/runner/builder &>/dev/null
cd /home/runner/builder || exit 1

echo "::group::Source Repo Sync"
printf "Initializing Repo\n"
python --version
python3 --version
python2 --version
printf "We will be using %s for Manifest source\n" "${MANIFEST}"
repo init -u ${MANIFEST} --depth=1 --groups=all,-notdefault,-device,-darwin,-x86,-mips || { printf "Repo Initialization Failed.\n"; exit 1; }
repo sync -c --force-sync --no-clone-bundle --no-tags -j6 || { printf "Git-Repo Sync Failed.\n"; exit 1; }
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
    cd /home/runner/builder || exit
fi
echo "::endgroup::"

echo "::group::Pre-Compilation"
printf "Compiling Recovery...\n"
export ALLOW_MISSING_DEPENDENCIES=true

# Only for (Unofficial) TWRP Building...
# If lunch throws error for roomservice, saying like `device tree not found` or `fetching device already present`,
# replace the `roomservice.py` with appropriate one according to platform version from here
# >> https://gist.github.com/rokibhasansagar/247ddd4ef00dcc9d3340397322051e6a/
# and then `source` and `lunch` again

source build/envsetup.sh
lunch omni_${CODENAME}-${FLAVOR} || { printf "Compilation failed.\n"; exit 1; }
echo "::endgroup::"

echo "::group::Compilation"
mka ${TARGET} || { printf "Compilation failed.\n"; exit 1; }
echo "::endgroup::"

# Export VENDOR, CODENAME and BuildPath for next steps
echo "VENDOR=${VENDOR}" >> ${GITHUB_ENV}
echo "CODENAME=${CODENAME}" >> ${GITHUB_ENV}
echo "BuildPath=/home/runner/builder" >> ${GITHUB_ENV}

# TODO:: Add GitHub Release Script Here
