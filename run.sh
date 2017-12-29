#!/bin/bash -e

name=$1
shift
nix build -f . -o result-$name $name $@

# Set mtime
touch result-$name

echo "Result written to ./result-$name"
