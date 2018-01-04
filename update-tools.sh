#!/usr/bin/env

bin=/home/ben/trec-car/mediawiki-annotate-release/bin
tools=$(nix eval --raw -f . carToolFiles)

mkdir -p car-tools
for tool in $tools; do
    version=$($bin/$tool --tool-version 2>/dev/null || echo 0)
    cp -L $bin/$tool car-tools/$tool.$version
    rm -f car-tools/$tool
    ln -s $(realpath car-tools)/$tool.$version car-tools/$tool
    echo "$tool    $version"
done

git -C $bin rev-parse HEAD > tools-commit
git -C $bin remote get-url origin > tools-remote
