bin=~/trec-car/mediawiki-annotate-release/bin
root_url=http://dumps.wikimedia.your.org/enwiki/20161220
embeddings=glove.6B.300d.txt 
version=v1.5.1
             
all : all.cbor.toc

download :
	wget -r --no-parent --accept '*-pages-articles[0-9]*.bz2' ${root_url}/

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



forbidden=--forbidden "see also" \
          --forbidden "references" \
          --forbidden "external links" \
          --forbidden "notes" \
          --forbidden "bibliography" \
	  --forbidden "gallery" \
	  --forbidden "publications" \
          --forbidden "further reading" \
	  --forbidden "track listing" \
	  --forbidden "sources" \
          --forbidden "cast" \
	  --forbidden "discography" \
	  --forbidden "awards" \
	  --forbidden "other" \
	  --forbidden "external links and references" \
  	  --forbidden "notes and references"

transformUnproc=--lead --image --shortHeading --longHeading --shortpage ${forbidden}
transformArticle=${forbidden}

preds='(!(${prefixMustPreds}) & !(${prefixMaybePreds}) & !is-redirect & !is-disambiguation & !(${categoryPreds}))'
articlepreds='(!(${prefixMustPreds})  & !is-redirect & !is-disambiguation & !name-has-prefix "Category:")'


transformed.%.cbor : %.cbor
	${bin}/trec-car-transform-content ${transformUnproc} omit.$< -o $@

filtered.%.cbor : %.cbor
	${bin}/trec-car-filter $< -o omit.$< ${preds}
	${bin}/trec-car-transform-content ${transformArticle} omit.$< -o $@


%.cbor.paragraphs %.cbor.outlines : %.cbor %.cbor.toc all.cbor
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
	${bin}/trec-car-transform-content $@.raw ${transformUnproc} -o $@ 


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
	${bin}/trec-car-transform-content ${transformArticle} trainomit.$< -o $@
	


test.cbor: processed.articles.cbor
	${bin}/trec-car-filter $< -o testomit.$< '(test-set)'
	${bin}/trec-car-transform-content -${transformArticle} testomit.$< -o $@
	
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




%.titles.zip : %
	${bin}/trec-car-dump titles $< | zip >| $@



archive-% : README.mkd LICENSE
	cp -f README.mkd $*/
	cp -f LICENSE $*/
	tar cvf $*-${version}.tar $*/



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







benchmark-% : 
test200set/all.test200.cbor : all.cbor
	${bin}/trec-car-filter all.cbor -o test200set/all.test200.cbor '( name-set-from-file "test200set/pagenames200.txt" )'



