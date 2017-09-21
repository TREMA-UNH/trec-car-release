ifeq "${CONFIG}" ""
$(error "No CONFIG value specified")
endif

include global-config.mk configs/${CONFIG}

all : all.cbor.toc

download :
	wget -r --no-parent --accept '*-pages-articles[0-9]*.bz2' ${root_url}

upload-% :
	 rsync -a $* dietz@lava:trec-car/public_html/datareleases/

#### Import
# Extract pages
%.cbor : %.bz2
	bzcat $< | ${bin}/trec-car-import > $@

all.pages : $(subst .bz2,.cbor,$(wildcard *.bz2))
	echo "all pages"

# Table of contents
%.cbor.toc : %.cbor
	${bin}/trec-car-build-toc pages $< > $@

%.cbor.paragraphs.toc : %.cbor.paragraphs
	${bin}/trec-car-build-toc paragraphs $< > $@


tocs : $(subst .bz2,.cbor.toc,$(wildcard *.bz2))

all.cbor : $(subst .bz2,.cbor,$(wildcard *.bz2))
	cat $+ > $@

#### TREC-CAR artifact extraction
# %.cbor.outlines : %.cbor %.cbor.toc unprocessed.train.cbor
#	${bin}/trec-car-export $< --unproc all.cbor


#### Filter
prefixMustPreds= name-has-prefix "Category talk:" | \
		name-has-prefix "Talk:" | \
		name-has-prefix "File:" | \
		name-has-prefix "File talk:" | \
		name-has-prefix "Special:" | \
		name-has-prefix "User:" | \
		name-has-prefix "User talk:" | \
		name-has-prefix "Wikipedia talk:" | \
		name-has-prefix "Wikipedia:" | \
		name-has-prefix "Template:" | \
		name-has-prefix "Template talk:" | \
		name-has-prefix "Module:" | \
		name-has-prefix "Draft:" | \
		name-has-prefix "Help:" | \
		name-has-prefix "Book:" | \
		name-has-prefix "TimedText:" | \
		name-has-prefix "MediaWiki:"
prefixMaybePreds= name-has-prefix "Category:" | \
								name-has-prefix "Portal:" | \
								name-has-prefix "List of " | \
								name-has-prefix "Lists of "
categoryPreds = category-contains " births" | \
								category-contains "deaths" | \
								category-contains " people" | \
								category-contains " event" | \
								category-contains " novels" | \
								category-contains " novel series" | \
								category-contains " books" | \
								category-contains " fiction" | \
								category-contains " plays" | \
								category-contains " films" | \
								category-contains " awards" | \
								category-contains " television series" | \
								category-contains " musicals" | \
								category-contains " albums" | \
								category-contains " songs" | \
								category-contains " singers" | \
								category-contains " artists" | \
								category-contains " music groups" | \
								category-contains " musical groups" | \
								category-contains " discographies" | \
								category-contains " concert tours" | \
								category-contains " albums" | \
								category-contains " soundtracks" | \
								category-contains " athletics clubs" | \
								category-contains "football clubs" | \
								category-contains " competitions" | \
								category-contains " leagues" | \
								category-contains " national register of historic places listings in " | \
								category-contains " by country" | \
								category-contains " by year" | \
								category-contains "years in " | \
								category-contains "years of the " | \
								category-contains "lists of "

preds='(!(${prefixMustPreds}) & !(${prefixMaybePreds}) & !is-redirect & !is-disambiguation & !(${categoryPreds}))'
articlepreds='(!(${prefixMustPreds})  & !is-redirect & !is-disambiguation & !name-has-prefix "Category:")'


transformed.%.cbor : %.cbor
	${bin}/trec-car-transform-content --sections-categories omit.$< -o $@

filtered.%.cbor : %.cbor
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

halfwiki.cbor : all.cbor
	${bin}/trec-car-filter $< -o $@ ${kbpreds}


articles.cbor : all.cbor
	${bin}/trec-car-filter $< -o $@.raw ${articlepreds}
	${bin}/trec-car-transform-content $@.raw --sections-categories -o $@


.PRECIOUS: %.dedup.cbor.duplicates
.PRECIOUS: processed.articles.cbor
.PRECIOUS: all.cbor
.PRECIOUS: articles.cbor.paragraphs

%.dedup.cbor.duplicates : %.cbor.paragraphs
	${bin}/trec-car-minhash-duplicates --embeddings ${embeddings} -t 0.9 --projections 12 -o $@ $< +RTS -N30 -A64M -s -RTS

%.dedup.cbor : %.cbor %.dedup.cbor.duplicates
	${bin}/trec-car-duplicates-rewrite-table -o $@.duplicates.table -d $@.duplicates
	${bin}/trec-car-rewrite-duplicates -o $@ -d $@.duplicates $<



processed.articles.cbor : articles.dedup.cbor
	${bin}/trec-car-filter $< -o $@ ${preds}


train.cbor: processed.articles.cbor
	${bin}/trec-car-filter $< -o trainomit.$< '(train-set)'
	${bin}/trec-car-transform-content --full trainomit.$< -o $@



test.cbor: processed.articles.cbor
	${bin}/trec-car-filter $< -o testomit.$< '(test-set)'
	${bin}/trec-car-transform-content --full testomit.$< -o $@

benchmark-train-% : train.cbor
	${bin}/trec-car-filter train.cbor -o $*/train.$*.cbor '( name-set-from-file "$*.titles.txt" )'

benchmark-test-% : test.cbor
	${bin}/trec-car-filter test.cbor -o $*/test.$*.cbor '( name-set-from-file "$*.titles.txt" )'

benchmark-% : train.cbor test.cbor
	${bin}/trec-car-filter train.cbor -o $*/train.$*.cbor '( name-set-from-file "$*/titles.txt" )'
	${bin}/trec-car-filter test.cbor -o $*/test.$*.cbor '( name-set-from-file "$*/titles.txt" )'


%.titles : %.cbor
	${bin}/trec-car-dump titles $< > $@


# -------v--------- drop ---------v----------



release-${version}.zip : filtered.all.cbor.paragraphs fold0.train.cbor.outlines fold1.train.cbor.outlines fold2.train.cbor.outlines fold3.train.cbor.outlines fold4.train.cbor.outlines fold0.test.cbor.outlines fold1.test.cbor.outlines fold2.test.cbor.outlines fold3.test.cbor.outlines fold4.test.cbor.outlines README.mkd
	rm -Rf release-${version}
	mkdir release-${version}
	cp fold*train.cbor fold*paragraphs fold*outlines fold*train*qrels README.mkd LICENSE release-${version}
	zip release-${version}.zip release-${version}/*

corpus-${version}.zip : README.mkd LICENSE filtered.all.cbor.paragraphs
	rm -Rf corpus-${version}
	mkdir corpus-${version}
	cp -f filtered.all.cbor.paragraphs corpus-${version}/release-${version}.paragraphs
	cp README.mkd LICENSE corpus-${version}/
	zip corpus-${version}.zip corpus-${version}/*




#%.tar.xz : % README.mkd LICENSE
#    tar cJvf $*-${version}.tar.xz $* README.mkd LICENSE

%.titles.zip : %
	${bin}/trec-car-dump titles $< | zip >| $@

archive-%.tar.xz : % %.outlines %.titles.zip README.mkd LICENSE
	tar cJvf $*-${version}.tar.xz $< $*.*.qrels


# archive-halfwiki.all.cbor

#make archive-halfwiki.cbor.tar.xz
#make archive-filtered.halfwiki.cbor.tar.xz

# filtered.%.cbor : %.cbor
#make filtered.all.cbor
#make filtered.halfwiki.cbor

#make filtered.all.cbor.paragraphs


archive-%.tar : README.mkd LICENSE
	cp -f README.mkd $*/
	cp -f LICENSE $*/
	tar cvf $*-${version}.tar $*/

archive-%.tar.xz : README.mkd LICENSE
	cp -f README.mkd $*/
	cp -f LICENSE $*/
	tar cJvf $*-${version}.tar.xz $*/

archive-% : archive-%.tar
	# done


%.fold0.cbor : %.cbor
	${bin}/trec-car-filter $< -o $@ "fold 0"

%.fold1.cbor : %.cbor
	${bin}/trec-car-filter $< -o $@ "fold 1"

%.fold2.cbor : %.cbor
	${bin}/trec-car-filter $< -o $@ "fold 2"

%.fold3.cbor : %.cbor
	${bin}/trec-car-filter $< -o $@ "fold 3"

%.fold4.cbor : %.cbor
	${bin}/trec-car-filter $< -o $@ "fold 4"




archive-paragraph.tar.xz : all.cbor README.mkd LICENSE
	${bin}/trec-car-transform-content --sections-categories all.cbor -o transformed.all.cbor
	${bin}/trec-car-build-toc pages transformed.all.cbor > transformed.all.cbor.toc
	${bin}/trec-car-export transformed.all.cbor -o paragraphcorpus.cbor
	#tar cJvf paragraphcorpus-${version}.tar.xz paragraphcorpus.cbor.paragraphs README.mkd LICENSE
	tar cvf paragraphcorpus-${version}.tar paragraphcorpus.cbor.paragraphs README.mkd LICENSE

archive-release.tar.xz : train.cbor README.mkd LICENSE
	# split train into folds
	# export fold -> outlines, qrels
	# package everything up



# .PHONY: release-halfwiki
# release-halfwiki : all.halfwiki.cbor README.mkd
#		tar cJvf halfwiki-${version}.tar.xz all.halfwiki.cbor README.mkd LICENSE


benchmark-% :
test200set/all.test200.cbor : all.cbor
	${bin}/trec-car-filter all.cbor -o test200set/all.test200.cbor '( name-set-from-file "test200set/pagenames200.txt" )'
