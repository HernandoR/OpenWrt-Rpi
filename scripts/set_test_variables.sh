#!/bin/bash
###
# @Author: Zhen Liu lzhen.dev@outlook.com
# @CreateDate: Do not edit
# @LastEditors: Zhen Liu lzhen.dev@outlook.com
# @LastEditTime: 2024-03-27
# @Description:
#
# Copyright (c) 2024 by HernandoR lzhen.dev@outlook.com, All Rights Reserved.
###

# Set test variables
export CONFIG_FILE="config/x86/64.config"
export SOURCE_URL="https://github.com/immortalwrt/immortalwrt"
export SOURCE_BRANCH="openwrt-23.05"
export DIY_SH="scripts/custom.sh"
export TOOLCHAIN_TAG="toolchain"
export CLASH_BINARY_PLATFORM="amd64"
export TOOLCHAIN_RELEASE_UPLOAD="true"
export FIRMWARE_RELEASE_UPLOAD="true"
export WEB_ROOT_PATH="/data/www/openwrt.cc"
export TZ="Asia/Shanghai"

export GITHUB_WORKSPACE="./"
export GITHUB_REPOSITORY="hernandoR/OpenWrt-Rpi"

export CURRENT_BRANCH="main"
export SOURCE_OWNER="immortalwrt"
export SOURCE_REPO="immortalwrt"
export DEVICE_PLATFORM="x86/64"
export DEVICE_TARGET="x86"
export DEVICE_SUBTARGET="64"
export TOOLCHAIN_IMAGE="toolchain-immortalwrt-${SOURCE_BRANCH}-${DEVICE_TARGET}-${DEVICE_SUBTARGET}"

export HOSTHATCH_IP="your-hosthatch-ip"
export REMOTE_USER="your-remote-user"
export HOSTHATCH_PRIVATEKEY="your-hosthatch-privatekey"

export B2_APPLICATION_KEY="your-b2-application-key"
export B2_APPLICATION_KEY_ID="your-b2-application-key-id"
export B2_BUCKETNAME="your-b2-bucketname"

export REBUILD_TOOLCHAIN="true"
