#!/bin/sh

remove_if_directory_exists() {
	if [ -d "$1" ]; then rm -Rf "$1"; fi
}

BRANCH="master";

REPOSITORY='git@github.com:tradingview/charting_library.git'

LATEST_HASH=$(git ls-remote $REPOSITORY $BRANCH | grep -Eo '^[[:alnum:]]+')

remove_if_directory_exists "$LATEST_HASH"

git clone -q --depth 1 -b "$BRANCH" $REPOSITORY "$LATEST_HASH"

remove_if_directory_exists "public/static/charting_library"
remove_if_directory_exists "public/static/datafeeds"

cp -r "$LATEST_HASH/charting_library" public/static
cp -r "$LATEST_HASH/datafeeds" public/static

remove_if_directory_exists "$LATEST_HASH"