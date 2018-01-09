#!/bin/bash -e

export NIX_PATH=/home/ben/

name=$1
shift
mkdir -p results
output="results/result-$name-$(date -Iseconds)"
nix build -f . -o $output $name --option cores 8 --option max-jobs 16 $@

# Set mtime
rm -f result-$name
ln -s `pwd`/$output result-$name
touch result-$name $output
find $output | xargs touch
chmod -R 755  $output

echo "Result written to ./result-$name"
echo "$(git rev-parse HEAD) $(date): $name $@" >> results/run.log
