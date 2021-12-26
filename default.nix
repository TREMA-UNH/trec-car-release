let
  config = rec {
    productName = "trec-car";
    lang = "en";
    wiki_name = "${lang}wiki";
    mirror_url = http://dumps.wikimedia.your.org/;
    import_config = ./config.en.yaml;
    # if lost, ressurect from here: jelly:/mnt/grapes/datasets/trec-car/duplicates.v1.5-table.xz
    duplicates-prev-table = /home/ben/trec-car/data/enwiki-20161220/release-v1.5/articles.dedup.cbor.duplicates.table;

    forbiddenHeadings = pkgs.lib.concatMapStringsSep " " (s: "--forbidden '${s}'") [
      "see also"
      "references"
      "external links"
      "notes"
      "bibliography"
      "gallery"
      "publications"
      "further reading"
      "track listing"
      "sources"
      "cast"
      "discography"
      "awards"
      "other"
      "external links and references"
      "notes and references"
    ];

    transformArticle = "${forbiddenHeadings}";
  };

  globalConfig = rec {
    version = "v2.4.2";
    dump_date = "20211220";
    lang_index = "lang-index";
    prefixMustPreds = ''
      name-has-prefix "Category talk:" |
      name-has-prefix "Talk:" |
      name-has-prefix "File:" |
      name-has-prefix "File talk:" |
      name-has-prefix "Special:" |
      name-has-prefix "User:" |
      name-has-prefix "User talk:" |
      name-has-prefix "Wikipedia talk:" |
      name-has-prefix "Wikipedia:" |
      name-has-prefix "Template:" |
      name-has-prefix "Template talk:" |
      name-has-prefix "Module:" |
      name-has-prefix "Draft:" |
      name-has-prefix "Help:" |
      name-has-prefix "Book:" |
      name-has-prefix "TimedText:" |
      name-has-prefix "MediaWiki:"
    '';
    prefixMaybePreds = ''
      name-has-prefix "Category:" |
      name-has-prefix "Portal:" |
      name-has-prefix "List of " |
      name-has-prefix "Lists of "
    '';
    categoryPreds = ''
      category-contains " births" |
      category-contains "deaths" |
      category-contains " people" |
      category-contains " event" |
      category-contains " novels" |
      category-contains " novel series" |
      category-contains " books" |
      category-contains " fiction" |
      category-contains " plays" |
      category-contains " films" |
      category-contains " awards" |
      category-contains " television series" |
      category-contains " musicals" |
      category-contains " albums" |
      category-contains " songs" |
      category-contains " singers" |
      category-contains " artists" |
      category-contains " music groups" |
      category-contains " musical groups" |
      category-contains " discographies" |
      category-contains " concert tours" |
      category-contains " albums" |
      category-contains " soundtracks" |
      category-contains " athletics clubs" |
      category-contains "football clubs" |
      category-contains " competitions" |
      category-contains " leagues" |
      category-contains " national register of historic places listings in " |
      category-contains " by country" |
      category-contains " by year" |
      category-contains "years in " |
      category-contains "years of the " |
      category-contains "lists of "
    '';
  };

  out_dir = "output/${config.productName}";

  pkgs = import <nixpkgs> { };
  inherit (pkgs) lib;
  inherit (pkgs.stdenv) mkDerivation;

  carToolNames = {
    build_toc         = "trec-car-build-toc";
    filter            = "trec-car-filter";
    export            = "trec-car-export";
    _import           = "trec-car-import";
    cat               = "trec-car-cat";
    dump              = "trec-car-dump";
    fill_metadata     = "trec-car-fill-metadata";
    transform_content = "trec-car-transform-content";
    multilang_car_index = "multilang-car-index";
    trec-car-minhash-duplicates = "trec-car-minhash-duplicates";
    trec-car-rewrite-duplicates = "trec-car-rewrite-duplicates";
    trec-car-duplicates-rewrite-table = "trec-car-duplicates-rewrite-table";
  };
  carTool = name: ./car-tools + "/${name}";
  carTools = lib.mapAttrs (_: carTool) carToolNames;


in rec {
  inherit carTools lib;
  carToolFiles = lib.concatStringsSep "\n" (lib.attrValues carToolNames);

  #lang_filter_opts = "--lang-index=${langIndex}/lang-index.cbor --from-site=${config.wiki_name}";
  lang_filter_opts = " ";

  # TOC file generation
  pagesTocFile = pagesFile: mkDerivation rec {
    name = "${pagesFile.name}.toc";
    passthru.pathname = name;
    buildInputs = [pagesFile];
    buildCommand = ''
      mkdir $out
      ln -s ${pagesFile}/pages.cbor $out/
      ${carTools.build_toc} pages $out/pages.cbor
      ${carTools.build_toc} page-names $out/pages.cbor
      ${carTools.build_toc} page-redirects $out/pages.cbor

    '';
  };

  parasTocFile = parasFile: mkDerivation rec {
    name = "${parasFile}.toc";
    passthru.pathname = name;
    buildInputs = parasFile;
    buildCommand = '' ${carTools.build_toc} paragraphs ${parasFile} > $out '';
  };

  dumps = (pkgs.callPackage ./wikimedia-dump.nix { inherit config globalConfig collectSymlinks; }).dumpsDownloadedTest;
  #dumps = (pkgs.callPackage ./wikimedia-dump.nix { inherit config globalConfig collectSymlinks; }).dumpsDownloaded;

  # GloVe embeddings
  glove = mkDerivation {
    name = "gloVe";
    passthru.pathname = "gloVe";
    nativeBuildInputs = [pkgs.unzip pkgs.python3];
    src = pkgs.fetchurl {
      name = "glove.zip";
      url = http://nlp.stanford.edu/data/glove.6B.zip;
      sha256 = "1yzjpjffv7v4pln2pjvwgyyi4hbgp5js9xxs6p18bl6bwqpznyk1";
    };
    buildCommand = let encodingFix = builtins.toFile "fix.py" ''
      import sys
      for i, line in enumerate(sys.stdin.buffer):
          try:
              sys.stdout.buffer.write(bytes(str(line, 'utf-8'), 'utf-8'))
          except UnicodeDecodeError:
              sys.stderr.buffer.write('Invalid codepoint on line %d' % i)
    '';
    in ''
      unzip $src
      ls -la
      mkdir $out
      # HACK
      python3 ${encodingFix} < glove.6B.50d.txt > $out/glove.6B.50d.txt
      #mv * $out
    '';
  };
  embedding = "${glove}/glove.6B.50d.txt";

  # -1. Inter-site page title index
  langIndex = ./lang-index; # name may change to 'lang-index.cbor'
  #langIndex = langIndex2;

  langIndex2 = mkDerivation {
    name = "lang-index";
    passthru.pathname = "lang-index.cbor";
    src = builtins.fetchurl {
      url = http://dumps.wikimedia.your.org/wikidatawiki/entities/20171204/wikidata-20171204-all.json.bz2;
      sha256 = "0ijrsk5znd3h46pmxhjxdhrpvda998rgqw0v1lrv0f8ysyb50x1g";
    };
    buildCommand = ''
      mkdir $out
      cd $out
      bzcat $src | ${carTools.multilang_car_index}
      mv out lang-index.cbor
    '';
  };

  # 0. all: Import
  rawPages =
    let
      dumpFiles = builtins.attrNames (builtins.readDir dumps.out);
      genRawPages = dumpFile: mkDerivation {
        name = "rawPagesSingle";
        passthru.pathname = "${dumpFile}-rawPages.cbor";
        buildCommand = ''
          mkdir $out
          bzcat ${dumpFile} | ${carTools._import} -c ${builtins.toPath config.import_config} --dump-date=${globalConfig.dump_date} --release-name="${config.productName} ${globalConfig.version}" -j$NIX_BUILD_CORES > $out/pages.cbor
        '';
      };

    in mkDerivation rec {
      name = "all.cbor";
      passthru.pathname = "all.cbor";
      buildInputs = map (f: genRawPages "${dumps.out}/${f}") dumpFiles;
      buildCommand = ''
        mkdir $out
	      ${carTools.cat} -o $out/pages.cbor ${pkgs.lib.concatMapStringsSep " " (f: "${f}/pages.cbor") buildInputs}
      '';
    };

  # 0.4: Kick out non-content pages
  contentPages = filterPages "content.cbor" rawPages '' (!(${globalConfig.prefixMustPreds})) '' "content.cbor";

  # 0.5: Fill redirect metadata
  fixRedirects = pages: mkDerivation {
    name = "fix-redirects";
    passthru.pathname = "fix-redirect.cbor";
    buildInputs = [ pages ];
    buildCommand = ''
      mkdir $out
      ${carTools.fill_metadata} --redirect -o $out/pages.cbor -i ${pages}/pages.cbor
    '';
  };

  redirectedPages =
    filterPages "filter-redirects" (fixRedirects contentPages)  "(!is-redirect)" "redirectedPages.cbor";

  # 0.6: Fill disambiguation and in-link metadata
  fixDisambig = pages: mkDerivation {
    name = "fix-disambig.cbor";
    passthru.pathname = "fix-disambig.cbor";
    buildInputs = [ pages ];
    buildCommand = ''
      mkdir $out
      ${carTools.fill_metadata} --disambiguation -o $out/pages.cbor -i ${pages}/pages.cbor
    '';
  };

  unprocessedAll = fixDisambig redirectedPages;

  # todo: fix order of definition (articles is defined below)
  unprocessedTrain = filterPages "unprocessed-train" articles "(train-set)" "unprocessedTrain.cbor";

  unprocessedTrainPackage = collectSymlinks {
    name = "unprocessedTrain-package";
    pathname = "unprocessedTrain.cbor";
    inputs = [license readme unprocessedTrain];
  };

  unprocessedAllPackage = collectSymlinks {
    name = "unprocessedAll-package";
    pathname = "unprocessedAll.cbor";
    inputs = [license readme unprocessedAll];
  };


  test200titles=./test200.titles;
  benchmarkY1titles=./benchmarkY1.titles;
  unprocessedAllButBenchmark = filterPages "allbutbenchmark" articles "((! name-set-from-file \"${test200titles}\") & (! name-set-from-file \"${benchmarkY1titles}\"))" "unprocessedAllButBenchmark.cbor";
  
  unprocessedAllButBenchmarkPackage = collectSymlinks {
    name = "unprocessedAllButBenchmark.cbor";
    pathname = "unprocessedAllButBenchmark.cbor";
    inputs = [license readme unprocessedAllButBenchmark] ++ (toFolds "unprocessedAllButBenchmark" unprocessedAllButBenchmark);
  };

  unprocessedPackage = collectSymlinks {
    name = "unprocessedPackage";
    pathname = "unprocessedPackage";
    inputs = [(buildArchive "unprocessedAllButBenchmark" unprocessedAllButBenchmarkPackage)
              (buildArchive "unprocessedTrain" unprocessedTrainPackage)
              (buildArchive "unprocessedAll" unprocessedAllPackage)
             ];
  };


  # 1. Drop non-article pages
  articles =
    filterPages "articles" unprocessedAll "(!is-disambiguation & !is-category)" "articles.cbor";

  articlesWithToc = pagesTocFile articles;
  laura = collectSymlinks2 {
    name = "laura";
    files =
      let
         toc = name: drv: {
          "${name}.cbor.toc" = "${drv}/pages.cbor.toc";
          "${name}.cbor" = "${drv}/pages.cbor";
        };
      in toc "raw" (pagesTocFile rawPages)
      // toc "articles" (pagesTocFile articles)
      // toc "content" (pagesTocFile contentPages)
      // toc "unprocessed-all" (pagesTocFile unprocessedAll)
      // toc "redirected" (pagesTocFile redirectedPages);
  };

  # 2. Drop administrative headings and category links
  processedArticles =
    let
      transformUnproc = "--lead --image --shortHeading --longHeading --shortpage ${config.forbiddenHeadings}";
    in mkDerivation {
      name = "proc.articles.cbor";
      passthru.pathname = "proc.articles.cbor";
      buildInputs = [articles];
      buildCommand = ''
        mkdir $out
        ${carTools.transform_content} ${articles}/pages.cbor -o $out/pages.cbor ${transformUnproc}
      '';
    };

  allParagraphs = exportParagraphs "all-paragraphs" processedArticles;

  # 3. Drop duplicate paragraphs

  # 3a. to run the duplicate detection $n$ times
  oneDuplicateMapping = seed: mkDerivation {
    name = "duplicate-mapping-${toString seed}";
    passthru.pathname = "duplicate-mapping-${toString seed}.duplicates";
    nativeBuildInputs = [ pkgs.glibcLocales ];
    buildInputs = [allParagraphs];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
	  ${carTools.trec-car-minhash-duplicates} --seed ${toString seed} --embeddings ${embedding} -t 0.9 --projections 24 -o $out/duplicates -c $out/bucket-counts ${allParagraphs}/paragraphs.cbor +RTS -N50 -A64M -s -RTS
    '';
  };

  duplicateMappings = sequentialize (lib.genList oneDuplicateMapping 5);
  # 3b. combine all detected duplicates
  combinedDuplicateMapping = mkDerivation {
    name = "combined-duplicate-mapping";
    passthru.pathname = "combined-duplicate-mapping.duplicates";
    buildInputs = duplicateMappings;
    buildCommand = ''
      mkdir $out
      cat ${lib.concatMapStringsSep " " (x: "${x}/duplicates") duplicateMappings} | sort -u > $out/duplicates
    '';
  };

  # 3c. create one duplicate table, which respects the canonical choices from v1.5
  duplicatesTable =
      mkDerivation {
        name = "duplicates.table";
        passthru.pathname = "duplicates.table";
        buildInputs = [combinedDuplicateMapping];
        buildCommand = ''
          mkdir $out
          ${carTools.trec-car-duplicates-rewrite-table} -o $out/duplicates.table -d ${combinedDuplicateMapping}/duplicates --table ${config.duplicates-prev-table}
        '';
      };

  # 3d. rewrite articles with new paragraph ids
  dedupArticles =
    let
      # Convenient way to temporarily disable the expensive deduplication step
      # for testing.
      runDedup = true;

      deduped = mkDerivation {
        name = "dedup.articles.cbor";
        passthru.pathname = "dedup.articles";
        buildInputs = [processedArticles duplicatesTable];
        buildCommand = ''
          mkdir $out
          ${carTools.trec-car-rewrite-duplicates} -o $out/pages.cbor -d ${duplicatesTable}/duplicates.table ${processedArticles}/pages.cbor
        '';
      };
    in if runDedup then deduped else processedArticles;

  # 3e. export deduplication data
  deduplicationPackage = collectSymlinks {
    name = "deduplication-package";
    pathname = "deduplication-package";
    inputs = [duplicatesTable] ++ duplicateMappings;
  };



  # ** Paragraph Corpus
  paragraphCorpus = exportParagraphs "paragraph-corpus" dedupArticles;

  paragraphCorpusPackage = collectSymlinks {
    name = "paragraphCorpus-package";
    pathname = "paragraphCorpus.cbor";
    inputs = [license readme paragraphCorpus];
  };
  paragraphCorpusArchive = buildArchive "paragraphCorpus" paragraphCorpusPackage;

  # 3. Drop pages of forbidden categories
  filtered =
    let
      preds = '' (!(${globalConfig.prefixMustPreds}) & !(${globalConfig.prefixMaybePreds}) & !is-redirect & !is-disambiguation & !(${globalConfig.categoryPreds})) '';
    in filterPages "filtered.cbor" dedupArticles preds "filtered.cbor";

  # 4. Drop, images, long/short sections, articles with <3 sections --(dont drop lead anymore!!)
  base =
    mkDerivation {
      name = "base.cbor";
      buildInputs = [filtered];
      passthru.pathname = "base.cbor";
      buildCommand = ''
        mkdir $out
        ${carTools.transform_content} ${config.forbiddenHeadings} ${filtered}/pages.cbor --lead -o $out/pages.cbor
      '';
    };

  # 5. Train/test split
  baseTest = filterPages "base.test.cbor" base "(test-set)" "base.test.cbor";
  baseTrain = filterPages "base.train.cbor" base "(train-set)" "base.train.cbor";

  # 6. Split train into folds
  toFolds = name: pagesFile:
    let fold = n:
      let nStr = toString n;
      in filterPages "${name}-fold-${nStr}" pagesFile "(fold ${nStr})" "fold-${nStr}-${pagesFile.pathname}";
    in builtins.genList fold 5;

  baseTrainFolds = toFolds "base-train" baseTrain;
  baseTrainAllFolds = collectSymlinks { name = "base-train-folds"; inputs = baseTrainFolds; pathname = "base-train";};

  # Readme
  readme = mkDerivation {
    name = "README.mkd";
    passthru.pathname = "README.mkd";
    buildCommand =
      let
        contents = builtins.toFile "README.mkd" ''
          This data set is part of the TREC CAR dataset version ${globalConfig.version}.

          The included TREC CAR data sets by Laura Dietz, Ben Gamari available
          at trec-car.cs.unh.edu are provided under a <a rel="license"
          href="http://creativecommons.org/licenses/by-sa/3.0/deed.en_US">Creative
          Commons Attribution-ShareAlike 3.0 Unported License</a>. The data is
          based on content extracted from www.Wikipedia.org that is licensed
          under the Creative Commons Attribution-ShareAlike 3.0 Unported
          License.

          mediawiki-annotate: ${builtins.readFile ./car-tools/tools-commit} in git repos ${builtins.readFile ./car-tools/tools-remote}
          build system: `git -C . rev-parse HEAD)` in git repos `git -C . remote get-url origin`
        '';
      in ''
        mkdir $out
        cp ${contents} $out/README.mkd
      '';
  };

  license = mkDerivation {
    name = "LICENSE";
    passthru.pathname = "LICENSE";
    buildCommand = ''
      mkdir $out
      cp ${./LICENSE} $out
    '';
  };

  # 8. Package
  trainPackage = collectSymlinks {
    name = "train-package";
    pathname = "train-package";
    inputs = [license readme baseTrain]
          ++ allExports ("train") baseTrain
          ++ baseTrainFolds
          ++ lib.concatMap (f: allExports ("train-"+f.name) f) baseTrainFolds;
  };

  trainArchive = buildArchive "train" trainPackage;

  # 9. Build benchmarks
  benchmarkPackages = basePages: name: titleList:
      let
        pages = filterPages "filtered-benchmark-${name}" basePages ''(name-set-from-file "${titleList}")'' "pages.cbor" ;
        test  = filterPages "${name}-test.cbor" pages "(test-set)" "test.pages.cbor";
        train = filterPages "${name}-train.cbor" pages "(train-set)" "train.pages.cbor";
        trainFolds = toFolds "${name}-train" train;
      in {
           trainPackage = collectSymlinks {
             name = "benchmark-${name}-train";
             pathname = "${name}-train";
             inputs = [
                 license
                 readme
                 train
                 (exportTitles train) (exportTopics train)
               ] ++ (allExports "${name}-train" train)
               ++ trainFolds
               ++ lib.concatMap (pagesFile: allExports pagesFile.name pagesFile) trainFolds;
           };
           testPackage = collectSymlinks {
             name = "benchmark-${name}-test";
             pathname = "${name}-test";
             inputs = [
               license readme
               test
               (exportTitles test)  (exportTopics test)
             ] ++ (allExports "${name}-test" test);
           };
           testPublicPackage = collectSymlinks {
             name = "benchmark-${name}-test-public";
             pathname = "${name}-test-public";
             inputs = [
               license readme
               (exportOutlines "${name}-test" test)
               (exportTitles test)  (exportTopics test)
             ];
           };
         };
  benchmarks = basePages: name: titleList:
     collectSymlinks {
       name = "benchmark-${name}";
       pathname = name;
       inputs = builtins.attrValues (benchmarkPackages basePages name titleList);
     };

  # Everything
  test200 = benchmarks base "test200" ./test200.titles;
  benchmarkY1 = benchmarks base "benchmarkY1" ./benchmarkY1.titles;
  deduplicationArchive = buildArchive "deduplication" deduplicationPackage;
  unprocessedTrainArchive = buildArchive "unprocessedTrain" unprocessedTrainPackage;
  unprocessedAllArchive = buildArchive "unprocessedAll" unprocessedAllPackage;
  unprocessedTrainToc = pagesTocFile unprocessedTrain;
  test200Archive = buildArchive "test200" (benchmarkPackages base "test200" ./test200.titles).trainPackage;
  benchmarkY1trainArchive = buildArchive "benchmarkY1train" (benchmarkPackages base "benchmarkY1" ./benchmarkY1.titles).trainPackage;
  benchmarkY1testArchive = buildArchive "benchmarkY1test" (benchmarkPackages base "benchmarkY1" ./benchmarkY1.titles).testPackage;
  benchmarkY1testPublicArchive = buildArchive "benchmarkY1test.public" (benchmarkPackages base "benchmarkY1" ./benchmarkY1.titles).testPublicPackage;


  all = collectSymlinks {
    pathname = "all";
    name = config.productName;
    inputs =
         [] #builtins.attrValues carTools
      ++ [
        (pagesTocFile rawPages)
        (pagesTocFile articles)
        (pagesTocFile unprocessedTrain)
        (pagesTocFile unprocessedAll)
        (pagesTocFile redirectedPages)
        paragraphCorpusArchive
        trainArchive
        test200
        benchmarkY1
        test200Archive
        benchmarkY1trainArchive
        benchmarkY1testArchive
        benchmarkY1testPublicArchive
        deduplicationArchive
        unprocessedTrainArchive
        unprocessedAllArchive
        unprocessedAllButBenchmarkPackage
      ];
  };


  ##########################################################
  # TREC CAR   template derivations
  ##########################################################

  export = {mode, output, pathname ? output, name, pagesFile}:
    let toc = pagesTocFile pagesFile;
    in mkDerivation {
      name = "export-${mode}-${name}";
      buildInputs = [ toc ];
      passthru.pathname = pathname;
      buildCommand = ''
        mkdir $out
        ${carTools.export} ${toc}/pages.cbor --${mode} $out/${output}
      '';
    };

  exportParagraphs = name: pagesFile:
    export {
      mode = "paragraphs";
      output = "paragraphs.cbor";
      pathname = "${baseNameOf pagesFile.pathname}-paragraphs.cbor";
      name = name;
      pagesFile = pagesFile;
    };
  exportOutlines = name: pagesFile:
    export {
      mode = "outlines";
      output = "outlines.cbor";
      pathname = "${baseNameOf pagesFile.pathname}-outlines.cbor";
      name = name;
      pagesFile = pagesFile;
    };
  exportQrel = mode: output: name: pagesFile:
      export {
        mode = mode;
        output =  "${output}.qrels";
        pathname = "${baseNameOf pagesFile.pathname}-${output}.qrels";
        name =  "${name}-${mode}";
        pagesFile = pagesFile;
      };

  allExports = name: pagesFile:
      [
        (exportParagraphs "${name}-paragraph" pagesFile)
        (exportOutlines "${name}-outlines" pagesFile)
        (exportQrel "para-hier-qrel"     "hierarchical" name pagesFile)
        (exportQrel "para-article-qrel"  "article" name pagesFile)
        (exportQrel "para-toplevel-qrel" "toplevel" name pagesFile)
        (exportQrel "entity-hier-qrel"     "hierarchical.entity" name pagesFile)
        (exportQrel "entity-article-qrel"  "article.entity" name pagesFile)
        (exportQrel "entity-toplevel-qrel" "toplevel.entity" name pagesFile)
      ];

  exportTitles = pagesFile: mkDerivation {
    name = "export-titles-${pagesFile.name}";
    passthru.pathname = "titles";
    nativeBuildInputs = [ pkgs.glibcLocales ];
    buildInputs = [pagesFile];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
      ${carTools.dump} titles ${pagesFile}/pages.cbor > $out/titles
    '';
  };

  exportTopics = pagesFile: mkDerivation {
    name = "export-topics-${pagesFile.name}";
    passthru.pathname = "topics";
    nativeBuildInputs = [ pkgs.glibcLocales ];
    buildInputs = [pagesFile];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
      ${carTools.dump} sections --raw ${pagesFile}/pages.cbor > $out/topics
    '';
  };

  filterPages = name: pagesFile: pred: pathname: mkDerivation {
    name = "filter-${name}";
    passthru.pathname = pathname;
    nativeBuildInputs = [ pkgs.glibcLocales ];
    buildInputs = [ pagesFile ];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
      ${carTools.filter} ${lang_filter_opts} ${pagesFile}/pages.cbor -o $out/pages.cbor '${pred}'
    '';
  };



  ##########################################################
  # Utilities  (independent of trec car)
  ##########################################################


  collectSymlinks2 = { name, files }: mkDerivation {
    name = name;
    buildCommand =
      pkgs.lib.concatStringsSep "\n"
      (["mkdir $out"] ++ pkgs.lib.mapAttrsToList (fname: file: "ln -s ${file} $out/${fname}") files);
  };

  overridePathName = pathName: drv: drv.overrideAttrs (_: { passthru.pathName = pathName; });

  rmEmpties = { name, drv }: mkDerivation {
    name = "rm-empties-${name}";
    buildInputs = [drv];
    buildCommand = ''
      for i in $(find -L ${drv} \( -type f -o -type l \) -a \! -empty -printf "%P\n"); do
        mkdir -p $(dirname $i)
        ln -s ${drv}/$i $out/$i
      done
    '';
  };

  impureFile = file: type: mkDerivation {
    name = "impure-${type}-${baseNameOf file}";
    src = [file];
    buildCommand = ''
      mkdir $out
      cp -L ${file} $out/${type}
    '';
   };

  collectSymlinks = { name, inputs, pathname, include ? null }: mkDerivation {
    name = "collect-${name}";
    buildInputs = inputs;
    passthru.pathname = pathname;
    buildCommand =
      let
        copyInput = input:
          ''
            nfiles=$(ls ${input} | wc -l)
            if [[ $nfiles == 1 ]]; then
              ln -s $(ls -d ${input}/*) $out/${input.pathname}
            elif [[ $nfiles > 1 ]]; then
              mkdir -p $out/${input.pathname}
              ln -s ${input}/* $out/${input.pathname}
            fi
          '';
      in ''
        mkdir $out
        ${pkgs.lib.concatMapStringsSep "\n" copyInput inputs}
      '';
  };

  buildArchive = name: deriv: mkDerivation {
    name = "archive-${name}";
    passthru.pathname = "archive-${name}.tar.xz";
    buildInputs = [
      deriv
    ];
    nativeBuildInputs = [pkgs.gnutar pkgs.xz];
    buildCommand = ''
      mkdir $out
      mkdir ${name}
      cp -rs ${deriv} ${name}
      find -type d | xargs chmod ug+wx
      tar --dereference -cJf $out/out.tar.xz ${name}
    '';
  };

  # Prevent nix from evaluating derivations in a list in parallel
  sequentialize = derivs:
    let f = drv: rest: builtins.seq (builtins.readDir drv.outPath) ([drv] ++ rest);
    in lib.foldr f [] derivs;
}
