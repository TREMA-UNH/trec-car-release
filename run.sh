#!/bin/bash -e

export NIX_PATH=/home/ben


name=$1
shift
mkdir -p results
start_time=$(date)
output="results/result-$name-$(date -Iseconds)"

# $max-jobs is number of jobs run in parallel, each job can use $cores many cpus
#nix-build . -A $name -o $output  --option cores 1 --option max-jobs 1 $@
nix build -f . -o $output $name --option cores 2 --option max-jobs 8 $@

# Set mtime
rm -f result-$name
ln -s $(pwd)/$output result-$name
touch result-$name $output
find $output | xargs touch
chmod -R 755  $output

echo "Result written to ./result-$name"
echo "$output: \t $(git rev-parse HEAD) \t started=$start_time \t finished=$(date) $name \t $@ " >> results/run.log
