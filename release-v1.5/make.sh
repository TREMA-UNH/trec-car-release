#! /bin/bash

# Needs
# LICENSE
# benchmarkY1.titles
# test200.titles


# RECOMMENDED
# all.cbor
# 

bin=~/trec-car/mediawiki-annotate-release/bin

function linkRaw {
	ln -s ../*bz2 .
}

function rawCbor {
	make -j3 -k
}


function createDir {
	dir="$1"
	
	echo "collect in directory ${dir}"
	rm -Rf ${dir}
	mkdir ${dir}
}


function archiveDir {
	dir="$1"
	rm ${dir}/*toc
	make archive-${dir}
}


function unprocessedtrain {
	make halfwiki.cbor
	cp halfwiki.cbor unprocessed.train.cbor
	make -d unprocessed.train.cbor.outlines

	dir="unprocessedtrain"
	
	createDir $dir
	cp unprocessed.train.cbor* $dir
	archiveDir $dir
		
}


function paragraph {
	echo "collecting files for paragraphcorpus"
	
	#drop name spaces, but preserve everything else
	make articles.dedup.cbor
	make articles.dedup.cbor.paragraphs

	dir="paragraphcorpus"
	createDir ${dir}

	cp articles.dedup.cbor.paragraphs ${dir}/paragraphcorpus.cbor
	
	archiveDir ${dir}
}

function trainfolds {
	echo "collecting files for train"

	createDir train
	
	make articles.dedup.cbor
	make train.cbor
	for fold in `seq 0 4`; do
		echo "Making fold ${fold}"
		make train.fold${fold}.cbor
		# make fold${fold}.train.cbor
		#${bin}/trec-car-filter train.cbor -o fold${fold}.train.cbor "fold ${fold}"
		make train.fold${fold}.cbor.outlines
		cp train.fold${fold}.cbor* train
	done
	
	archiveDir train
}


function benchmarks-train {
	dir="$1"
	pagefile="$2"

	echo "Create benchmark ${dir}"
	createDir $dir
	
	cp -sf ${pagefile} ${dir}.titles.txt
	
	make benchmark-train-${dir}
	make ${dir}/train.${dir}.cbor.outlines
	make ${dir}/train.${dir}.titles

	for fold in `seq 0 4`; do
		echo "Making fold ${fold}"
		make ${dir}/train.${dir}.fold${fold}.cbor
		# make fold${fold}.train.cbor
		#${bin}/trec-car-filter train.cbor -o fold${fold}.train.cbor "fold ${fold}"
		make ${dir}/train.${dir}.fold${fold}.cbor.outlines
		make ${dir}/train.${dir}.fold${fold}.titles

	find ${dir}/ -empty -delete
	done
	
	
	archiveDir $dir
}	

function benchmarks-test {
	dir="$1"
	pagefile="$2"

	echo "Create benchmark ${dir}"
	createDir $dir
	cp -sf ${pagefile} ${dir}.titles.txt




	make benchmark-test-${dir}
	make ${dir}/test.${dir}.cbor.outlines
	make ${dir}/test.${dir}.titles

	#find ${dir}/ -empty -delete
	
	
	archiveDir $dir
}	

function test200 {
	benchmarks-train test200 test200.titles
}	
function benchmarkY1 {
	benchmarks-train benchmarkY1train benchmarkY1.titles
	benchmarks-test benchmarkY1test benchmarkY1.titles
}	


	
	#make train.cbor/test.cbor
	#filter page names
	#create folds
	

function makeprecious {
	make articles.cbor.toc
	make articles.cbor.paragraphs
}	

function all {
	# linkRaw
	# rawCbor
	unprocessedtrain
	paragraph
	trainfolds
	test200
	benchmarkY1
}



$@
