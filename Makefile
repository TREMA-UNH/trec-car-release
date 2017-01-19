bin=~/trec-car/mediawiki-annotate/bin
root_url=http://dumps.wikimedia.your.org/enwiki/20161220
version=v1.3
             
all : all.cbor.json

download :
	wget -r --no-parent --accept '*-pages-articles[0-9]*.bz2' ${root_url}
             
#### Import  
# Extract pages
%.cbor : %.bz2
	bzcat $< | ${bin}/trec-car-import > $@
all.pages : $(subst .bz2,.cbor,$(wildcard *.bz2))

# Table of contents
%.cbor.json : %.cbor
	${bin}/trec-car-build-toc < $< > $@

tocs : $(subst .bz2,.cbor.json,$(wildcard *.bz2))

all.cbor : $(subst .bz2,.cbor,$(wildcard *.bz2))
	cat $+ > $@

#### TREC-CAR artifact extraction
%.cbor.outlines : %.cbor %.cbor.json
	${bin}/trec-car-export $<

#### Baselines
# Corpus statistics
%.cbor.stats : %.cbor %.cbor.json
	${bin}/car-test corpus-stats -o $@ $<

all.stats : $(subst .bz2,.cbor.stats,$(wildcard *.bz2))
	${bin}/car-test merge-corpus-stats -o $@ $+

# Paragraph index
%.cbor.index : %.cbor %.cbor.json
	${bin}/car-test index -o $@ $<

all.index : $(subst .bz2,.cbor.index,$(wildcard *.bz2))
	${bin}/car-test merge -o $@ $+

run : all.index all.stats


#### EQFE Knowledge-base extraction
%.warc : %.cbor
	${bin}/trec-car-extract-kb -o $@ $< +RTS -s -RTS


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
prefixMaybePreds= name-has-prefix "Category:" | 
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

preds='(!(${prefixMustPreds}) & !(${prefixMaybePreds}) & !is-redirect & !is-disambiguation &  &!(${categoryPreds}))'

all-omit-pages.cbor : all.cbor
	${bin}/trec-car-filter all.cbor -o $@ ${preds}


transformed-omit-pages.cbor : all-omit-pages.cbor
	${bin}/trec-car-transform-content all-omit-pages.cbor -o $@

train.cbor : transformed-omit-pages.cbor
	${bin}/trec-car-filter transformed-omit-pages.cbor -o $@ train-set


fold%.train.cbor : train.cbor train.cbor.json
	${bin}/trec-car-filter $< -o $@ "fold $*"

spritzerPreds='(name-in-set ["Green sea turtle", "Hydraulic Fracturing", "Spent nuclear fuel", "Spent nuclear fuel", "Sustainable biofuel", "Behavior of nuclear fuel during a reactor accident"])'
spritzer.cbor : transformed-omit-pages.cbor transformed-omit-pages.cbor.json
	${bin}/trec-car-filter $< -o $@ ${spritzerPreds}

all.cbor.paragraphs : transformed-omit-pages.cbor transformed-omit-pages.cbor.json
	${bin}/trec-car-export $< -o all.cbor 

%.cbor.outlines : %.cbor %.cbor.json
	${bin}/trec-car-export $< -o $<


clean-export-% :
	echo rm -f $*.outlines $*.paragraph $**.qrels


.PHONY : README.mkd
README.mkd : 
	echo "This data set is part of the TREC CAR dataset version ${version}.\nThe included TREC CAR data sets by Laura Dietz, Ben Gamari available at trec-car.cs.unh.edu are provided under a <a rel="license" href="http://creativecommons.org/licenses/by-sa/3.0/deed.en_US">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>. The data is based on content extracted from www.Wikipedia.org that is licensed under the Creative Commons Attribution-ShareAlike 3.0 Unported License." > README.mkd

.PHONY: release
release : release-${version}.zip corpus-${version}.zip

release-${version}.zip : all.cbor.paragraphs fold0.train.cbor.outlines fold1.train.cbor.outlines fold2.train.cbor.outlines fold3.train.cbor.outlines fold4.train.cbor.outlines README.mkd 
	rm -R release-${version}
	mkdir release-${version}
	cp fold*train.cbor fold*paragraphs fold*outlines fold*train*qrels README.mkd LICENSE release-${version}
	zip release-${version}.zip release-${version}/*

corpus-${version}.zip : README.mkd LICENSE all.cbor.paragraphs
	rm -R corpus-${version}
	mkdir corpus-${version}
	cp -f all.cbor.paragraphs corpus-${version}/release-${version}.paragraphs
	cp README.mkd LICENSE corpus-${version}/
	zip corpus-${version}.zip corpus-${version}/*

.PHONY: cleancorpus
cleancorpus:
	echo rm -f all.cbor.paragraphs corpus-${version}.zip                                                                                                                     
.PHONY: cleanrelease
cleanrelease : cleancorpus clean-export-fold*.train.cbor
	echo -f rm release-${version}.zip 

.PHONY : spritzer
spritzer : spritzer.cbor.outlines README.mkd
	zip spritzer-${version}.zip spritzer.cbor.outlines spritzer.cbor spritzer.cbor.paragraphs spritzer*qrels README.mkd LICENSE

.PHONY : cleanspritzer
cleanspritzer : clean-spritzer.cbor
	echo rm -f spritzer-${version}.zip


# build galago index
# # Galago build index
#To build an index modify paths in simplir-galago.json and run:
##
#    java -jar ./target/simplir-galago-1.0-SNAPSHOT-jar-with-dependencies.jar build simplir-galago.json 
#
#Paths must be global and you should double check that the job-tmp directory is empty before starting (or it will try to finish indexing the last attempt).


kbpreds='(!(${prefixMustPreds}) & train-set)'
%.halfwiki.cbor : %.cbor
	${bin}/trec-car-filter $< -o $@ ${kbpreds}	


%.linkcontexts.warc : %.cbor
	${bin}/trec-car-extract-link-contexts $< -o $@

%.kb.warc : %.cbor
	${bin}/trec-car-extract-kb $< -o $@
 


%.linkcontexts.index : %.linkcontexts.warc
	java -jar ${bin}/galago.jar build --indexPath=$@ --inputPath=$< --galagoJobDir=/tmp/galagojob-$@-tmp linkcontexts-galago.json


%.kb.index : %.kb.warc
	java -jar ${bin}/galago.jar build --indexPath=$@ --inputPath=$< --galagoJobDir=/tmp/galagojob-$@-tmp kb-galago.json

%.index.search : %.index
	java -jar ${bin}/galago.jar search --port=2507 --index=$<

.PHONY: release-kb
%.release-kb.zip : %.kb.index %.linkcontexts.index %.kb.warc %.linkcontexts.warc
	zip -r $@ $+

clean-%.release-kb : 
	echo rm -f $*.release-kb.zip $*.kb.index $*.linkcontexts.index $*.kb.warc $*.linkcontexts.warc

