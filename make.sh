#!/bin/bash -ex

# Needs
# LICENSE
# benchmarkY1.titles
# test200.titles


# RECOMMENDED
# all.cbor
#

if [ -f ./.local-config ]; then
  source .local-config
fi

if [ -z "$bin" ]; then
  bin=~/trec-car/mediawiki-annotate-release/bin
fi

export bin CONFIG
out=$(make show VALUE=out_dir)
version=$(make show VALUE=version)

function download {
  make download
}

function linkRaw {
  make mk_dump_links
}

function rawCbor {
  make -j3 -k
}


function createDir {
  local dir="$1"

  echo "collect in directory ${dir}"
  #rm -Rf ${dir}
  mkdir -p ${dir}
}


function archiveDir {
  local dir="$1"
  #rm -f ${dir}/*toc
  pwd
	cp -f README.mkd $*/
	cp -f LICENSE $*/
	tar cvf $*-${version}.tar $*/
}


function unprocessedtrain {
  make $out/halfwiki.cbor
  cp $out/halfwiki.cbor $out/unprocessed.train.cbor
  make $out/unprocessed.train.cbor.outlines

  local dir="unprocessedtrain"

  createDir $dir
  cp $out/unprocessed.train.cbor* $dir
  archiveDir $dir
}


function paragraph {
  echo "collecting files for paragraphcorpus"

  #drop name spaces, but preserve everything else
  make $out/articles.dedup.cbor
  make $out/articles.dedup.cbor.paragraphs

  local dir="$out/paragraphcorpus"
  createDir ${dir}

  cp $out/articles.dedup.cbor.paragraphs ${dir}/paragraphcorpus.cbor

  archiveDir ${dir}
}

function trainfolds {
  echo "collecting files for train"

  createDir $out/train

  make $out/articles.dedup.cbor
  make $out/train.cbor
  for fold in `seq 0 4`; do
    echo "Making fold ${fold}"
    make $out/train.fold${fold}.cbor
    # make fold${fold}.train.cbor
    #${bin}/trec-car-filter train.cbor -o fold${fold}.train.cbor "fold ${fold}"
    make $out/train.fold${fold}.cbor.outlines
    cp $out/train.fold${fold}.cbor* $out/train
  done

  archiveDir $out/train
}


function benchmarks-train {
  local dir="$1"
  local pagefile="$2"

  echo "Create benchmark ${dir}"
  createDir ${out}/$dir

  ln -sfr ${pagefile} ${dir}.titles.txt

  make benchmark-train-${dir}
  make ${out}/${dir}/train.${dir}.cbor.outlines
  make ${out}/${dir}/train.${dir}.titles

  for fold in `seq 0 4`; do
    echo "Making fold ${fold}"
    make ${out}/${dir}/train.${dir}.fold${fold}.cbor
    # make fold${fold}.train.cbor
    #${bin}/trec-car-filter train.cbor -o fold${fold}.train.cbor "fold ${fold}"
    make ${out}/${dir}/train.${dir}.fold${fold}.cbor.outlines
    find ${out}/${dir}/ -empty -delete
    make ${out}/${dir}/train.${dir}.fold${fold}.titles
  done

  archiveDir $out/$dir
}

function benchmarks-test {
  local dir="$1"
  local pagefile="$2"

  echo "Create benchmark ${dir}"
  createDir $out/$dir
  ln -sfr ${pagefile} ${dir}.titles.txt

  make benchmark-test-${dir}
  make $out/${dir}/test.${dir}.cbor.outlines
  find ${out}/${dir}/ -empty -delete
  make $out/${dir}/test.${dir}.titles

  archiveDir $out/$dir
}

function test200 {
  benchmarks-train test200 test200.titles
}
function benchmarkY1 {
  benchmarks-train benchmarkY1train benchmarkY1.titles
  benchmarks-test benchmarkY1test benchmarkY1.titles

  createDir $out/benchmarkY1test.public
  #cp $out/benchmarkY1test/titles $out/benchmarkY1test.public/
  cp $out/benchmarkY1test/test.benchmarkY1test.titles $out/benchmarkY1test.public/
  cp $out/benchmarkY1test/test.benchmarkY1test.cbor.outlines $out/benchmarkY1test.public/

  archiveDir $out/benchmarkY1test.public
}



  #make train.cbor/test.cbor
  #filter page names
  #create folds


function makeprecious {
  make articles.cbor.toc
  make articles.cbor.paragraphs
}

function raw {
  echo "making linkRaw"
  linkRaw

  echo "making rawCbor"
  rawCbor
}

function all {
  echo "making unprocessedtrain"
  unprocessedtrain

  echo "making paragraph"
  paragraph

  echo "making trainfolds"
  trainfolds

  echo "making test200"
  test200

  echo "making benchmarkY1"
  benchmarkY1
}


$@
