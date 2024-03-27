#!/bin/bash

set -e

# Define functions for each step
initialization_environment() {
    sudo rm -rf /etc/apt/sources.list.d/* /usr/share/dotnet /usr/local/lib/android /opt/ghc
    sudo -E apt-get -qq update
    sudo -E apt-get -qq install squashfs-tools $(curl -fsSL git.io/depends-ubuntu-2004)
    sudo -E apt-get -qq autoremove --purge
    sudo -E apt-get -qq clean
    sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    docker image prune -a -f
    mkdir -p workspace
}

clone_source_code() {
    df -hT $PWD
    git clone $SOURCE_URL -b $SOURCE_BRANCH workspace/openwrt
    cd workspace/openwrt
    echo "OPENWRT_ROOT_PATH=$PWD" >>$GITHUB_ENV
    echo "OPENWRT_ROOT_PATH=$(echo $PWD)" >>$GITHUB_OUTPUT
}

generate_toolchain_config() {
    [ -e $CONFIG_FILE ] && mv $CONFIG_FILE $OPENWRT_ROOT_PATH/.config
    echo -e "\nCONFIG_ALL=y" >>$OPENWRT_ROOT_PATH/.config
    echo -e "\nCONFIG_ALL_NONSHARED=y" >>$OPENWRT_ROOT_PATH/.config
    cd $OPENWRT_ROOT_PATH
    make defconfig >/dev/null 2>&1
}

generate_variables() {
    export CURRENT_BRANCH="$(git symbolic-ref --short HEAD)"
    echo "CURRENT_BRANCH=$CURRENT_BRANCH" >>$GITHUB_ENV
    echo "CURRENT_BRANCH=$(echo $CURRENT_BRANCH)" >>$GITHUB_OUTPUT
    cd $OPENWRT_ROOT_PATH
    export SOURCE_OWNER="$(echo $SOURCE_URL | awk -F '/' '{print $(NF-1)}')"
    echo "SOURCE_OWNER=$SOURCE_OWNER" >>$GITHUB_ENV
    echo "SOURCE_OWNER=$(echo $SOURCE_OWNER)" >>$GITHUB_OUTPUT
    export SOURCE_REPO="$(echo $SOURCE_URL | awk -F '/' '{print $(NF)}')"
    echo "SOURCE_REPO=$SOURCE_REPO" >>$GITHUB_ENV
    echo "SOURCE_REPO=$(echo $SOURCE_REPO)" >>$GITHUB_OUTPUT
    export DEVICE_TARGET=$(cat .config | grep CONFIG_TARGET_BOARD | awk -F '"' '{print $2}')
    echo "DEVICE_TARGET=$DEVICE_TARGET" >>$GITHUB_ENV
    echo "DEVICE_TARGET=$(echo $DEVICE_TARGET)" >>$GITHUB_OUTPUT
    export DEVICE_SUBTARGET=$(cat .config | grep CONFIG_TARGET_SUBTARGET | awk -F '"' '{print $2}')
    echo "DEVICE_SUBTARGET=$DEVICE_SUBTARGET" >>$GITHUB_ENV
    echo "DEVICE_SUBTARGET=$(echo $DEVICE_SUBTARGET)" >>$GITHUB_OUTPUT
    export DEVICE_PLATFORM=$(cat .config | grep CONFIG_TARGET_ARCH_PACKAGES | awk -F '"' '{print $2}')
    echo "DEVICE_PLATFORM=$DEVICE_PLATFORM" >>$GITHUB_ENV
    echo "DEVICE_PLATFORM=$(echo $DEVICE_PLATFORM)" >>$GITHUB_OUTPUT
    export TOOLCHAIN_IMAGE="toolchain-$SOURCE_OWNER-$SOURCE_REPO-$SOURCE_BRANCH-$DEVICE_TARGET-$DEVICE_SUBTARGET"
    echo "TOOLCHAIN_IMAGE=$TOOLCHAIN_IMAGE" >>$GITHUB_ENV
    echo "TOOLCHAIN_IMAGE=$(echo $TOOLCHAIN_IMAGE)" >>$GITHUB_OUTPUT
}

compare_toolchain_hash() {
    cd $OPENWRT_ROOT_PATH
    export CURRENT_HASH=$(git log --pretty=tformat:"%H" -n1 tools toolchain)
    echo "CURRENT_HASH=$CURRENT_HASH" >>$GITHUB_ENV
    echo "CURRENT_HASH=$(echo $CURRENT_HASH)" >>$GITHUB_OUTPUT
    echo "CURRENT_HASH is $CURRENT_HASH"
    export CACHE_HASH=$(curl -fSsL https://github.com/$GITHUB_REPOSITORY/releases/download/$TOOLCHAIN_TAG/$TOOLCHAIN_IMAGE.hash)
    echo "CACHE_HASH is $CACHE_HASH"
    if [ -z "$CACHE_HASH" ] || [ "$CURRENT_HASH" != "$CACHE_HASH" ]; then
        echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_OUTPUT
    fi
}

install_feeds() {
    if [ "$REBUILD_TOOLCHAIN" == "true" ]; then
        cd $OPENWRT_ROOT_PATH
        ./scripts/feeds update -a
        ./scripts/feeds install -a
        make defconfig
    fi
}

compile_tools() {
    if [ "$REBUILD_TOOLCHAIN" == "true" ]; then
        cd $OPENWRT_ROOT_PATH
        echo -e "$(nproc) thread compile"
        make tools/compile -j$(nproc) || make tools/compile -j1 V=s
    fi
}

compile_toolchain() {
    if [ "$REBUILD_TOOLCHAIN" == "true" ]; then
        cd $OPENWRT_ROOT_PATH
        echo -e "$(nproc) thread compile"
        make toolchain/compile -j$(nproc) || make toolchain/compile -j1 V=s
        rm -rf .config* dl bin
    fi
}

generate_toolchain_image() {
    if [ "$REBUILD_TOOLCHAIN" == "true" ]; then
        cd workspace
        mksquashfs openwrt $TOOLCHAIN_IMAGE -force-gid 1001 -force-uid 1001 -comp zstd
        mkdir -p $GITHUB_WORKSPACE/output
        split -d -b 1900M $TOOLCHAIN_IMAGE $GITHUB_WORKSPACE/output/$TOOLCHAIN_IMAGE.img.
        rm $TOOLCHAIN_IMAGE
        cd $OPENWRT_ROOT_PATH
        echo $CURRENT_HASH >$GITHUB_WORKSPACE/output/toolchain-$SOURCE_OWNER-$SOURCE_REPO-$SOURCE_BRANCH-$DEVICE_TARGET-$DEVICE_SUBTARGET.hash
        ls -lh $GITHUB_WORKSPACE/output
    fi
}

upload_toolchain_image_to_artifact() {
    if [ "$REBUILD_TOOLCHAIN" == "true" ] && [ "$TOOLCHAIN_RELEASE_UPLOAD" != "true" ]; then
        # Use `actions/upload-artifact` action in GitHub Actions
        echo "Uploading toolchain image to artifact"
    fi
}

delete_old_toolchain_assets_from_release() {
    if [ "$REBUILD_TOOLCHAIN" == "true" ] && [ "$TOOLCHAIN_RELEASE_UPLOAD" == "true" ]; then
        # Use `mknejp/delete-release-assets` action in GitHub Actions
        echo "Deleting old toolchain assets from release"
    fi
}

upload_toolchain_image_to_release() {
    if [ "$REBUILD_TOOLCHAIN" == "true" ] && [ "$TOOLCHAIN_RELEASE_UPLOAD" == "true" ]; then
        # Use `ncipollo/release-action` action in GitHub Actions
        echo "Uploading toolchain image to release"
    fi
}

# Call functions in the correct order
initialization_environment
clone_source_code
generate_toolchain_config
generate_variables
compare_toolchain_hash
install_feeds
compile_tools
compile_toolchain
generate_toolchain_image
upload_toolchain_image_to_artifact
delete_old_toolchain_assets_from_release
upload_toolchain_image_to_release
