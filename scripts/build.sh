#!/bin/bash

set -e

# Define functions for each step
restore_variables() {
    echo "CURRENT_BRANCH=$(echo '${{needs.Toolchain.outputs.CURRENT_BRANCH}}')" >>$GITHUB_ENV
    echo "OPENWRT_ROOT_PATH=$(echo '${{needs.Toolchain.outputs.OPENWRT_ROOT_PATH}}')" >>$GITHUB_ENV
    echo "SOURCE_OWNER=$(echo '${{needs.Toolchain.outputs.SOURCE_OWNER}}')" >>$GITHUB_ENV
    echo "SOURCE_REPO=$(echo '${{needs.Toolchain.outputs.SOURCE_REPO}}')" >>$GITHUB_ENV
    echo "DEVICE_PLATFORM=$(echo '${{needs.Toolchain.outputs.DEVICE_PLATFORM}}')" >>$GITHUB_ENV
    echo "DEVICE_TARGET=$(echo '${{needs.Toolchain.outputs.DEVICE_TARGET}}')" >>$GITHUB_ENV
    echo "DEVICE_SUBTARGET=$(echo '${{needs.Toolchain.outputs.DEVICE_SUBTARGET}}')" >>$GITHUB_ENV
    echo "TOOLCHAIN_IMAGE=$(echo '${{needs.Toolchain.outputs.TOOLCHAIN_IMAGE}}')" >>$GITHUB_ENV
}

initialization_environment() {
    sudo rm -rf /etc/apt/sources.list.d/* /usr/share/dotnet /usr/local/lib/android /opt/ghc
    sudo -E apt-get -qq update
    sudo -E apt-get -qq install rdate squashfs-tools $(curl -fsSL git.io/depends-ubuntu-2004)
    sudo -E apt-get -qq autoremove --purge
    sudo -E apt-get -qq clean
    sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    docker image prune -a -f
}

combine_disks() {
    sudo swapoff -a
    sudo rm -f /mnt/swapfile
    export ROOT_FREE_KB=$(df --block-size=1024 --output=avail / | tail -1)
    export ROOT_LOOP_KB=$(expr $ROOT_FREE_KB - 1048576)
    export ROOT_LOOP_BYTES=$(expr $ROOT_LOOP_KB \* 1024)
    sudo fallocate -l $ROOT_LOOP_BYTES /root.img
    export ROOT_LOOP_DEVNAME=$(sudo losetup -Pf --show /root.img)
    sudo pvcreate -f $ROOT_LOOP_DEVNAME
    export MNT_FREE_KB=$(df --block-size=1024 --output=avail /mnt | tail -1)
    export MNT_LOOP_KB=$(expr $MNT_FREE_KB - 102400)
    export MNT_LOOP_BYTES=$(expr $MNT_LOOP_KB \* 1024)
    sudo fallocate -l $MNT_LOOP_BYTES /mnt/mnt.img
    export MNT_LOOP_DEVNAME=$(sudo losetup -Pf --show /mnt/mnt.img)
    sudo pvcreate -f $MNT_LOOP_DEVNAME
    sudo vgcreate vgstorage $ROOT_LOOP_DEVNAME $MNT_LOOP_DEVNAME
    sudo lvcreate -n lvstorage -l 100%FREE vgstorage
    export LV_DEVNAME=$(sudo lvscan | awk -F "'" '{print $2}')
    sudo mkfs.btrfs -L combinedisk $LV_DEVNAME
    sudo mount -o compress=zstd $LV_DEVNAME $GITHUB_WORKSPACE
    sudo chown -R runner:runner $GITHUB_WORKSPACE
    mkdir $GITHUB_WORKSPACE/tmp
    chmod 777 $GITHUB_WORKSPACE/tmp
    sudo cp -rp /tmp/* $GITHUB_WORKSPACE/tmp
    sudo mount -B $GITHUB_WORKSPACE/tmp /tmp
    df -hT $GITHUB_WORKSPACE
    sudo btrfs filesystem usage $GITHUB_WORKSPACE
}

checkout() {
    cd $GITHUB_WORKSPACE
    git init
    git remote add origin https://github.com/$GITHUB_REPOSITORY
    git fetch
    git checkout -t origin/$CURRENT_BRANCH
}

download_toolchain_image_from_artifacts() {
    if [ "$TOOLCHAIN_RELEASE_UPLOAD" != "true" ]; then
        # Use `actions/download-artifact` action in GitHub Actions
        echo "Downloading toolchain image from artifacts"
    fi
}

prepare_toolchain_image_from_artifacts() {
    if [ "$TOOLCHAIN_RELEASE_UPLOAD" != "true" ]; then
        cd workspace
        for i in {1..9}; do
            cat $TOOLCHAIN_IMAGE.img.0$i >>$TOOLCHAIN_IMAGE.img.00 && rm $TOOLCHAIN_IMAGE.img.0$i || break
        done
        mv $TOOLCHAIN_IMAGE.img.00 $TOOLCHAIN_IMAGE.img
        mkdir openwrt-ro openwrt workdir overlay
        sudo mount -o loop $TOOLCHAIN_IMAGE.img openwrt-ro
        sudo mount -t overlay overlay -o lowerdir=openwrt-ro,upperdir=overlay,workdir=workdir openwrt
        cd $OPENWRT_ROOT_PATH
        git pull
    fi
}

prepare_toolchain_image_from_releases() {
    if [ "$TOOLCHAIN_RELEASE_UPLOAD" == "true" ]; then
        mkdir -p workspace
        cd workspace
        for i in {0..9}; do
            curl -fsL https://github.com/$GITHUB_REPOSITORY/releases/download/$TOOLCHAIN_TAG/$TOOLCHAIN_IMAGE.img.0$i >>$TOOLCHAIN_IMAGE.img || break
        done
        mkdir openwrt-ro openwrt workdir overlay
        sudo mount -o loop $TOOLCHAIN_IMAGE.img openwrt-ro
        sudo mount -t overlay overlay -o lowerdir=openwrt-ro,upperdir=overlay,workdir=workdir openwrt
        cd $OPENWRT_ROOT_PATH
        git pull
    fi
}

install_feeds() {
    cd $OPENWRT_ROOT_PATH
    ./scripts/feeds update -a
    ./scripts/feeds install -a
}

load_custom_configuration() {
    [ -e files ] && mv files $OPENWRT_ROOT_PATH/files
    [ -e $CONFIG_FILE ] && mv $CONFIG_FILE $OPENWRT_ROOT_PATH/.config
    cat config/general-packages.config >>$OPENWRT_ROOT_PATH/.config
    cat config/extra-drivers.config >>$OPENWRT_ROOT_PATH/.config
    cd $OPENWRT_ROOT_PATH
    chmod +x $GITHUB_WORKSPACE/scripts/*.sh
    $GITHUB_WORKSPACE/$DIY_SH
    $GITHUB_WORKSPACE/scripts/preset-clash-core.sh $CLASH_BINARY_PLATFORM
    $GITHUB_WORKSPACE/scripts/preset-terminal-tools.sh
    make defconfig
}

download_dl_package() {
    cd $OPENWRT_ROOT_PATH
    make download -j64
}

compile_packages() {
    cd $OPENWRT_ROOT_PATH
    echo -e "$(nproc) thread compile"
    make buildinfo
    make diffconfig buildversion feedsversion
    make target/compile -j$(nproc) IGNORE_ERRORS="m n" BUILD_LOG=1 ||
        yes n | make target/compile -j1 V=s IGNORE_ERRORS=1
    make package/compile -j$(nproc) IGNORE_ERRORS=1 || make package/compile -j1 V=s IGNORE_ERRORS=1
    make package/index
}

generate_firmware() {
    if grep -q $DEVICE_TARGET/$DEVICE_SUBTARGET $GITHUB_WORKSPACE/data/support-targets.txt; then
        mkdir -p $OPENWRT_ROOT_PATH/files/etc/opkg
        cd $OPENWRT_ROOT_PATH/files/etc/opkg
        cp $GITHUB_WORKSPACE/data/opkg/distfeeds.conf .
        sed -i "s/DEVICE_SUBTARGET/$DEVICE_SUBTARGET/g" distfeeds.conf
        sed -i "s/DEVICE_TARGET/$DEVICE_TARGET/g" distfeeds.conf
        sed -i "s/DEVICE_PLATFORM/$DEVICE_PLATFORM/g" distfeeds.conf
        cd $OPENWRT_ROOT_PATH
        git clone https://git.openwrt.org/project/usign.git
        cd usign
        cmake .
        make
        sudo mv usign /bin
        mkdir -p $OPENWRT_ROOT_PATH/files/etc/opkg/keys
        cd $OPENWRT_ROOT_PATH/files/etc/opkg/keys
        wget -q https://openwrt.cc/keys/key-build.pub
        mv key-build.pub $(usign -F -p key-build.pub)
    fi
    cd $OPENWRT_ROOT_PATH
    mkdir -p files/etc/uci-defaults/
    cp $GITHUB_WORKSPACE/scripts/init-settings.sh files/etc/uci-defaults/99-init-settings
    mkdir -p files/www/snapshots
    cp -r bin/targets files/www/snapshots
    make package/install -j$(nproc) || make package/install -j1 V=s
    make target/install -j$(nproc) || make target/install -j1 V=s
    make json_overview_image_info
    make checksum
}

print_sha256sums() {
    cd $OPENWRT_ROOT_PATH/bin/targets/$DEVICE_TARGET/$DEVICE_SUBTARGET
    cat sha256sums
}

compress_bin_folder() {
    cd $OPENWRT_ROOT_PATH
    zip -r $DEVICE_TARGET-$DEVICE_SUBTARGET.zip bin
}

print_disk_usage() {
    echo 'lsblk -f'
    lsblk -f
    echo '-----'
    echo 'df -h'
    df -h
    echo '-----'
    echo 'btrfs filesystem usage'
    sudo btrfs filesystem usage $GITHUB_WORKSPACE
    echo '-----'
}

upload_bin_archive() {

    # Use actions/upload-artifact action in GitHub Actions
    echo "Uploading bin archive"
}

Call functions in the correct order
restore_variables
initialization_environment
combine_disks
checkout
download_toolchain_image_from_artifacts
prepare_toolchain_image_from_artifacts
prepare_toolchain_image_from_releases
install_feeds
load_custom_configuration
download_dl_package
compile_packages
generate_firmware
print_sha256sums
compress_bin_folder
print_disk_usage
upload_bin_archive
