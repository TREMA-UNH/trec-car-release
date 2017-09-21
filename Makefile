ifeq "${CONFIG}" ""
$(error "No CONFIG value specified")
endif

include global-config.mk configs/${CONFIG}

out_dir=output/${product_name}

all : ${out_dir} all.cbor.toc

${out_dir} :
	mkdir -p $@

download :
	mkdir -p dumps
	#wget --directory-prefix=dumps -nd -c -r --no-parent --accept '*-pages-articles[0-9]*.bz2' ${root_url}
.PHONY : download

# The file paths of the raw .xml.bz2 files
dump_files=$(wildcard dumps/${wiki_name}-${dump_date}*.bz2)
# The basenames of the dump files.
# e.g. enwiki-20170901-pages-articles2.xml-p30304p88444
dumps=$(basename $(notdir ${dump_files}))

#### Import
mk_dump_links : download
	ln -sf ${dump_files} ${out_dir}
.PHONY : mk_dump_links

# Create raw articles files
${out_dir}/%.cbor : ${dump_files}
	bzcat $< | ${bin}/trec-car-import --dump-date=${dump_date} --release-name="${product_name} ${version}" -j8 > $@

# Table of contents
%.cbor.toc : %.cbor
	${bin}/trec-car-build-toc pages $< > $@

%.cbor.paragraphs.toc : ${out_dir}/%.cbor.paragraphs
	${bin}/trec-car-build-toc paragraphs $< > $@


tocs : $(addprefix ${out_dir}/,$(addsuffix .cbor.toc,${dumps}))
.PHONY : tocs

${out_dir}/all.cbor : $(addprefix ${out_dir}/,$(addsuffix .cbor,${dumps}))
	cat $+ > $@

#### TREC-CAR artifact extraction
# %.cbor.outlines : %.cbor %.cbor.toc unprocessed.train.cbor
#	${bin}/trec-car-export $< --unproc all.cbor

%.transformed.cbor : %.cbor
	${bin}/trec-car-transform-content --sections-categories omit.$< -o $@

%.filtered.cbor : %.cbor
	${bin}/trec-car-filter $< -o omit.$< ${preds}
	${bin}/trec-car-transform-content --full omit.$< -o $@


%.cbor.paragraphs : %.cbor %.cbor.toc unprocessed.train.cbor
	${bin}/trec-car-export $< -o $*.cbor --unproc all.cbor

%.cbor.outlines : %.cbor %.cbor.toc unprocessed.train.cbor
	${bin}/trec-car-export $< -o $*.cbor --unproc all.cbor



.PHONY : README.mkd
README.mkd :
	echo "This data set is part of the TREC CAR dataset version ${version}.\nThe included TREC CAR data sets by Laura Dietz, Ben Gamari available at trec-car.cs.unh.edu are provided under a <a rel="license" href="http://creativecommons.org/licenses/by-sa/3.0/deed.en_US">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>. The data is based on content extracted from www.Wikipedia.org that is licensed under the Creative Commons Attribution-ShareAlike 3.0 Unported License." > README.mkd
	echo "" >> README.mkd
	echo "mediawiki-annotate: $(git -C $bin rev-parse HEAD)" >> README.mkd
	echo "build system: $(git -C . rev-parse HEAD)" >> README.mkd


kbpreds='(!(${prefixMustPreds}) & train-set)'
namespacepreds='(!(${prefixMustPreds}))'

${out_dir}/halfwiki.cbor : ${out_dir}/all.cbor
	${bin}/trec-car-filter $< -o $@ ${kbpreds}


${out_dir}/articles.cbor : ${out_dir}/all.cbor
	${bin}/trec-car-filter $< -o $@.raw ${articlepreds}
	${bin}/trec-car-transform-content $@.raw --sections-categories -o $@
	rm $@.raw

.PRECIOUS: %.dedup.cbor.duplicates
.PRECIOUS: processed.articles.cbor
.PRECIOUS: all.cbor
.PRECIOUS: articles.cbor.paragraphs

%.dedup.cbor.duplicates : %.cbor.paragraphs
	${bin}/trec-car-minhash-duplicates --embeddings ${embeddings} -t 0.9 --projections 12 -o $@ $< +RTS -N30 -A64M -s -RTS

%.dedup.cbor : %.cbor %.dedup.cbor.duplicates
	${bin}/trec-car-duplicates-rewrite-table -o $@.duplicates.table -d $@.duplicates
	${bin}/trec-car-rewrite-duplicates -o $@ -d $@.duplicates $<
	rm $@.duplicates.table


${out_dir}/processed.articles.cbor : ${out_dir}/articles.dedup.cbor
	${bin}/trec-car-filter $< -o $@ ${preds}


${out_dir}/train.cbor: ${out_dir}/processed.articles.cbor
	${bin}/trec-car-filter $< -o trainomit.$< '(train-set)'
	${bin}/trec-car-transform-content --full trainomit.$< -o $@
	rm trainomit.$<

${out_dir}/test.cbor: ${out_dir}/processed.articles.cbor
	${bin}/trec-car-filter $< -o testomit.$< '(test-set)'
	${bin}/trec-car-transform-content --full testomit.$< -o $@
	rm testomit.$<

benchmark-train-% : ${out_dir}/train.cbor
	${bin}/trec-car-filter $< -o ${out_dir}/$*/train.$*.cbor '( name-set-from-file "$*.titles.txt" )'

benchmark-test-% : ${out_dir}/test.cbor
	${bin}/trec-car-filter $< -o ${out_dir}/$*/test.$*.cbor '( name-set-from-file "$*.titles.txt" )'

benchmark-% : ${out_dir}/train.cbor ${out_dir}/test.cbor
	${bin}/trec-car-filter ${out_dir}/train.cbor -o ${out_dir}/$*/train.$*.cbor '( name-set-from-file "$*/titles.txt" )'
	${bin}/trec-car-filter ${out_dir}/test.cbor -o ${out_dir}/$*/test.$*.cbor '( name-set-from-file "$*/titles.txt" )'

folds-% : $(foreach $(shell seq 0 4),fold,%.fold${fold}.cbor)

%.titles : %.cbor
	${bin}/trec-car-dump titles $< > $@

archive-%.tar : README.mkd LICENSE
	cp -f README.mkd $*/
	cp -f LICENSE $*/
	tar cvf $*-${version}.tar $*/

%.xz : %
	xz $<

archive-% : archive-%.tar

upload-% :
	 rsync -a $* dietz@lava:trec-car/public_html/datareleases/
