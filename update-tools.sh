#!/usr/bin/env bash

#bin=/home/ben/trec-car/mediawiki-annotate-release/bin
if [ -z "$bin" ]; then echo "\$bin not set"; exit 1; fi

tools=$(nix eval --extra-experimental-features nix-command --raw -f . carToolFiles)

mkdir -p car-tools
for tool in $tools; do
    version=$($bin/$tool --tool-version 0>/dev/null 2>/dev/null || echo 0)
    cp -L $bin/$tool car-tools/$tool.$version
    rm -f car-tools/$tool
    ln -s $(realpath car-tools)/$tool.$version car-tools/$tool
    echo "$tool    $version"
done

git -C $bingit rev-parse HEAD > car-tools/tools-commit
git -C $bingit remote get-url origin > car-tools/tools-remote
