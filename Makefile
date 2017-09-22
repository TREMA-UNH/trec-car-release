ifeq "${CONFIG}" ""
$(error "No CONFIG value specified")
endif

include global-config.mk
include configs/${CONFIG}

out_dir=output/${product_name}

lang_filter_opts=--lang-index=${lang_index} --from-site=${wiki_name}

all : ${out_dir} ${out_dir}/all.cbor.toc

show :
	@echo ${${VALUE}}

${out_dir} :
	mkdir -p $@

download : dumps/.stamp-${wiki_name}/${dump_date}
.PHONY : download

dumps/.stamp-${wiki_name}/${dump_date} :
	mkdir -p dumps
	wget --directory-prefix=dumps -nd -c -r --no-parent --accept '*-pages-articles[0-9]*.bz2' ${root_url}
	touch $@

# The file paths of the raw .xml.bz2 files
dump_files=$(wildcard dumps/${wiki_name}-${dump_date}*.bz2)
# The basenames of the dump files.
# e.g. enwiki-20170901-pages-articles2.xml-p30304p88444
dumps=$(basename $(notdir ${dump_files}))

#### Import
mk_dump_links : ${out_dir} download
	for i in ${dump_files}; do ln -sf ../../$$i ${out_dir}; done;
.PHONY : mk_dump_links

# Create raw articles files
${out_dir}/%.raw.cbor : dumps/%.bz2
	bzcat $< | ${bin}/trec-car-import -c ${import_config} --dump-date=${dump_date} --release-name="${product_name} ${version}" -j8 > $@

${out_dir}/all.cbor : $(addprefix ${out_dir}/,$(addsuffix .raw.cbor,${dumps}))
	cat $+ > $@

# Table of contents
%.cbor.paragraphs.toc : ${out_dir}/%.cbor.paragraphs
	${bin}/trec-car-build-toc paragraphs $< > $@

%.cbor.toc : %.cbor
	${bin}/trec-car-build-toc pages $< > $@

tocs : $(addprefix ${out_dir}/,$(addsuffix .cbor.toc,${dumps}))
.PHONY : tocs

#### TREC-CAR artifact extraction
# %.cbor.outlines : %.cbor %.cbor.toc unprocessed.train.cbor
#	${bin}/trec-car-export $< --unproc all.cbor

%.transformed.cbor : %.cbor
	${bin}/trec-car-transform-content ${transformUnproc} omit.$< -o $@

%.filtered.cbor : %.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o omit.$< ${preds}
	${bin}/trec-car-transform-content ${transformArticle} omit.$< -o $@


%.cbor.paragraphs %.cbor.outlines : %.cbor %.cbor.toc ${out_dir}/all.cbor
	${bin}/trec-car-export $< -o $*.cbor --unproc ${out_dir}/all.cbor


README.mkd :
	echo "This data set is part of the TREC CAR dataset version ${version}.\nThe included TREC CAR data sets by Laura Dietz, Ben Gamari available at trec-car.cs.unh.edu are provided under a <a rel="license" href="http://creativecommons.org/licenses/by-sa/3.0/deed.en_US">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>. The data is based on content extracted from www.Wikipedia.org that is licensed under the Creative Commons Attribution-ShareAlike 3.0 Unported License." > README.mkd                                                                                                                                                                               echo "" >> README.mkd
	echo "mediawiki-annotate: `git -C ${bin} rev-parse HEAD)` in git repos `git -C ${bin} remote get-url origin`  " >> README.mkd
	echo "build system: `git -C . rev-parse HEAD)` in git repos `git -C . remote get-url origin`" >> README.mkd                                                                                                                                                                                                                             
	

kbpreds='(!(${prefixMustPreds}) & train-set)'
namespacepreds='(!(${prefixMustPreds}))'

${out_dir}/halfwiki.cbor : ${out_dir}/all.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o $@ ${kbpreds}


${out_dir}/articles.cbor : ${out_dir}/all.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o $@.raw ${articlepreds}
	${bin}/trec-car-transform-content $@.raw ${transformUnproc} -o $@
	rm $@.raw

.PRECIOUS: %.dedup.cbor.duplicates
.PRECIOUS: processed.articles.cbor
.PRECIOUS: all.cbor
.PRECIOUS: articles.cbor.paragraphs

${out_dir}/%.dedup.cbor.duplicates : ${out_dir}/%.cbor.paragraphs
	${bin}/trec-car-minhash-duplicates --embeddings ${embeddings} -t 0.9 --projections 12 -o $@ $< +RTS -N30 -A64M -s -RTS

%.dedup.cbor : %.cbor %.dedup.cbor.duplicates
	${bin}/trec-car-duplicates-rewrite-table -o $@.duplicates.table -d $@.duplicates
	${bin}/trec-car-rewrite-duplicates -o $@ -d $@.duplicates $<
	rm $@.duplicates.table


${out_dir}/processed.articles.cbor : ${out_dir}/articles.dedup.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o $@ ${preds}


${out_dir}/train.cbor: ${out_dir}/processed.articles.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o ${out_dir}/trainomit '(train-set)'
	${bin}/trec-car-transform-content ${out_dir}/trainomit ${transformArticle} -o $@
	rm ${out_dir}/trainomit

${out_dir}/test.cbor: ${out_dir}/processed.articles.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o ${out_dir}/testomit '(test-set)'
	${bin}/trec-car-transform-content ${out_dir}/testomit ${transformArticle} -o $@
	rm ${out_dir}/testomit

benchmark-train-% : ${out_dir}/train.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o ${out_dir}/$*/train.$*.cbor '( name-set-from-file "$*.titles.txt" )'

benchmark-test-% : ${out_dir}/test.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o ${out_dir}/$*/test.$*.cbor '( name-set-from-file "$*.titles.txt" )'

benchmark-% : benchmark-train-% benchmark-test-%

folds-% : $(foreach $(shell seq 0 4),fold,%.fold${fold}.cbor)

%.fold0.cbor : %.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o $@ "fold 0"
%.fold1.cbor : %.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o $@ "fold 1"
%.fold2.cbor : %.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o $@ "fold 2"
%.fold3.cbor : %.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o $@ "fold 3"
%.fold4.cbor : %.cbor
	${bin}/trec-car-filter ${lang_filter_opts} $< -o $@ "fold 4"

%.titles : %.cbor
	${bin}/trec-car-dump titles $< > $@


# Package a single file with license info
package-% : % README.mkd LICENSE
	tar cvf $*.tar $+




upload-% :
	 rsync -a $* dietz@lava:trec-car/public_html/datareleases/
