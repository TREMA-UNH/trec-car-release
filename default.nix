let
  config = rec {
    productName = "trec-car";
    lang = "en";
    wiki_name = "${lang}wiki";
    mirror_url = http://dumps.wikimedia.your.org/;
    import_config = ./config.en.yaml;

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
    version = "v1.6";
    dump_date = "20161220";
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

  root_url = "${config.mirror_url}${config.wiki_name}/${globalConfig.dump_date}";
  out_dir = "output/${config.productName}";
  bin = /home/ben/trec-car/mediawiki-annotate-release/bin;

  pkgs = import <nixpkgs> { };
  inherit (pkgs.stdenv) mkDerivation;

  carTool = name: "${bin}/${name}";
  #carTool = name: mkDerivation {
  #  name = "car-tool-${name}";
  #  inputs = [ (builtins.toPath "${bin}/${name}") ];
  #  buildCommand = ''
  #    mkdir $out
  #    cp ${bin}/${name} $out/exe
  #  '';
  #};

  #trec_car_build_toc = builtins.toPath "${bin}/trec-car-build-toc";
  carTools = {
    build_toc = carTool "trec-car-build-toc";
    filter = carTool "trec-car-filter";
    export = carTool "trec-car-export";
    _import = carTool "trec-car-import";
    cat    = carTool "trec-car-cat";
    dump   = carTool "trec-car-dump";
    fill_metadata    = carTool "trec-car-fill-metadata";
    transform_content = carTool "trec-car-transform-content";
  };

in rec {
  inherit carTools;

  lang_filter_opts = "--lang-index=${langIndex}/lang-index.cbor --from-site=${config.wiki_name}";

  # TOC file generation

  pagesTocFile = pagesFile: mkDerivation {
    name = "${pagesFile.name}.toc";
    buildInputs = [pagesFile];
    buildCommand = ''
      mkdir $out
      ln -s ${pagesFile}/pages.cbor $out/
      ${carTools.build_toc} pages $out/pages.cbor
    '';
  };

  parasTocFile = parasFile: mkDerivation {
    name = "${parasFile}.toc";
    buildInputs = parasFile;
    buildCommand = '' ${carTools.build_toc} paragraphs ${parasFile} > $out '';
  };

  # Dump file preparation
  dumpStatus = mkDerivation {
    name = "dump-${config.wiki_name}-${globalConfig.dump_date}-status";
    src = pkgs.fetchurl {
      name = "dumpstatus.json";
      url = "${root_url}/dumpstatus.json";
      sha256 = null;
    };
    buildCommand = ''
      mkdir $out
      cp $src $out/dumpstatus.json
    '';
  };

  dumps = dumpsLocal;

  dumpsLocal = mkDerivation {
    name = "dump-local";
    buildCommand = ''
      mkdir $out
      ln -s /home/ben/trec-car/data/enwiki-20161220/*.bz2 $out
    '';
  };

  dumpsDownloaded = collectSymlinks {
    name = "dump-${config.wiki_name}-${globalConfig.dump_date}";
    inputs =
      let
        download = name: meta: mkDerivation {
          name = "dump-${config.wiki_name}-${globalConfig.dump_date}-${name}";
          src = pkgs.fetchurl {
            name = name;
            url = "${config.mirror_url}${meta.url}";
            sha1 = meta.sha1;
          };
          buildCommand = ''
            mkdir $out
            cp $src $out
          '';
        };
        metadata = builtins.fromJSON (builtins.readFile "${dumpStatus}/dumpstatus.json");
      in pkgs.lib.mapAttrsToList download metadata.jobs.articlesdump.files;
  };

  dumpsOld = mkDerivation {
    name = "dump-${config.wiki_name}-${globalConfig.dump_date}";
    buildInputs = [ pkgs.wget ];
    buildCommand = ''
      mkdir $out
	    wget --directory-prefix $out -nd -c -r --no-parent --accept '*-pages-articles[0-9]*.bz2' ${root_url} || test $? = 8
	    #wget --directory-prefix $out -nd -c -r --no-parent --accept '*-pages-articles1.*.bz2' ${root_url} || test $? = 8
    '';
  };

  # GloVe embeddings
  glove = mkDerivation {
    name = "gloVe";
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
  langIndex = ./lang-index;
  #langIndex = langIndex2;

  langIndex2 = mkDerivation {
    name = "lang-index";
    src = builtins.fetchurl {
      url = http://dumps.wikimedia.your.org/wikidatawiki/entities/20171204/wikidata-20171204-all.json.bz2;
      sha256 = "0ijrsk5znd3h46pmxhjxdhrpvda998rgqw0v1lrv0f8ysyb50x1g";
    };
    buildCommand = ''
      mkdir $out
      cd $out
      bzcat $src | ${carTool "multilang-car-index"}
      mv out lang-index.cbor
    '';
  };

  # 0. all: Import
  rawPages =
    let
      dumpFiles = builtins.attrNames (builtins.readDir dumps.out);
      genRawPages = dumpFile: mkDerivation {
        name = "rawPagesSingle";
        buildCommand = ''
          mkdir $out
          bzcat ${dumpFile} | ${carTools._import} -c ${builtins.toPath config.import_config} --dump-date=${globalConfig.dump_date} --release-name="${config.productName} ${globalConfig.version}" -j$NIX_BUILD_CORES > $out/pages.cbor
        '';
      };

    in mkDerivation rec {
      name = "all.cbor";
      buildInputs = map (f: genRawPages "${dumps.out}/${f}") dumpFiles;
      buildCommand = ''
        mkdir $out
	      ${carTools.cat} -o $out/pages.cbor ${pkgs.lib.concatMapStringsSep " " (f: "${f}/pages.cbor") buildInputs}
      '';
    };

  # 0.4: Kick out non-content pages
  contentPages = filterPages "content.cbor" rawPages '' (!(${globalConfig.prefixMustPreds})) '';

  # 0.5: Fill redirect metadata
  fixRedirects = pages: mkDerivation {
    name = "fix-redirects";
    buildInputs = [ pages ];
    buildCommand = ''
      mkdir $out
      ${carTools.fill_metadata} --redirect -o $out/pages.cbor -i ${pages}/pages.cbor
    '';
  };

  redirectedPages =
    filterPages "filter-redirects" (fixRedirects contentPages)
    "(!is-redirect)";

  # 0.6: Fill disambiguation and in-link metadata
  fixDisambig = pages: mkDerivation {
    name = "fix-disambig.cbor";
    buildInputs = [ pages ];
    buildCommand = ''
      mkdir $out
      ${carTools.fill_metadata} --disambiguation -o $out/pages.cbor -i ${pages}/pages.cbor
    '';
  };

  unprocessedAll = fixDisambig redirectedPages;

  unprocessedTrain = filterPages "unprocessed-train" articles "(train-set)";

  # 1. Drop non-article pages
  articles =
    filterPages "articles" unprocessedAll
    "(!is-disambiguation & !is-category)";

  articlesWithToc = pagesTocFile articles;
  laura = collectSymlinks { name = "hi"; inputs = [
    (pagesTocFile articles)
    (pagesTocFile rawPages)
    (contentPages)
    (unprocessedAll)
    (redirectedPages)
  ]; };

  # 2. Drop administrative headings and category links
  processedArticles =
    let
      transformUnproc = "--lead --image --shortHeading --longHeading --shortpage ${config.forbiddenHeadings}";
    in mkDerivation {
      name = "proc.articles.cbor";
      buildInputs = [articles];
      buildCommand = ''
        mkdir $out
        ${carTools.transform_content} ${articles}/pages.cbor -o $out/pages.cbor ${transformUnproc}
      '';
    };

  allParagraphs = exportParagraphs "all-paragraphs" processedArticles;

  # 3. Drop duplicate paragraphs
  duplicateMapping = mkDerivation {
    name = "duplicate-mapping";
    buildInputs = [allParagraphs];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
	    ${carTool "trec-car-minhash-duplicates"} --embeddings ${embedding} -t 0.9 --projections 24 -o $out/duplicates -c $out/bucket-counts ${allParagraphs}/paragraphs.cbor +RTS -N50 -A64M -s -RTS
    '';
  };

  dedupArticles =
    let
      # Convenient way to temporarily disable the expensive deduplication step
      # for testing.
      runDedup = true;

      deduped = mkDerivation {
        name = "dedup.articles.cbor";
        buildInputs = [processedArticles duplicateMapping];
        buildCommand = ''
          mkdir $out
          ${carTool "trec-car-duplicates-rewrite-table"} -o $out/duplicates.table -d ${duplicateMapping}/duplicates
          ${carTool "trec-car-rewrite-duplicates"} -o $out/pages.cbor -d ${duplicateMapping}/duplicates ${processedArticles}/pages.cbor
        '';
      };
    in if runDedup then deduped else processedArticles;

  paragraphCorpus = exportParagraphs "paragraph-corpus" dedupArticles;

  # 3. Drop pages of forbidden categories
  filtered =
    let
      preds = '' (!(${globalConfig.prefixMustPreds}) & !(${globalConfig.prefixMaybePreds}) & !is-redirect & !is-disambiguation & !(${globalConfig.categoryPreds})) '';
    in filterPages "filtered.cbor" dedupArticles preds;

  # 4. Drop lead, images, long/short sections, articles with <3 sections
  base =
    mkDerivation {
      name = "base.cbor";
      buildInputs = [filtered];
      buildCommand = ''
        mkdir $out
        ${carTools.transform_content} ${config.forbiddenHeadings} ${filtered}/pages.cbor -o $out/pages.cbor
      '';
    };

  # 5. Train/test split
  baseTest = filterPages "base.test.cbor" base "(test-set)";
  baseTrain = filterPages "base.train.cbor" base "(train-set)";

  # 6. Split train into folds
  toFolds = name: pagesFile:
    let fold = n: filterPages "${name}-fold-${toString n}" pagesFile "(fold ${toString n})";
    in builtins.genList fold 5;

  baseTrainFolds = toFolds "base-train" base;
  baseTrainAllFolds = collectSymlinks { name = "base-train-folds"; inputs = baseTrainFolds; };

  # Readme
  readme = mkDerivation {
    name = "README.mkd";
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

          mediawiki-annotate: `git -C ${bin} rev-parse HEAD)` in git repos `git -C ${bin} remote get-url origin`
          build system: `git -C . rev-parse HEAD)` in git repos `git -C . remote get-url origin`
        '';
      in ''
        mkdir $out
        cp ${contents} $out/README.mkd
      '';
  };

  license = mkDerivation {
    name = "LICENSE";
    buildCommand = ''
      mkdir $out
      cp ${./LICENSE} $out
    '';
  };

  # 8. Package
  trainPackage = collectSymlinks {
    name = "train-package";
    inputs = [license readme] ++ map (f: exportAll ("train-"+f.name) f) baseTrainFolds;
  };

  trainArchive = buildArchive "train" trainPackage;

  # 9. Build benchmarks
  benchmarkPackages = name: titleList:
      let
        pages = filterPages "filtered-benchmark-${name}" base ''(name-set-from-file "${titleList}")'';
        test  = filterPages "${name}-test.cbor" pages "(test-set)";
        train = filterPages "${name}-train.cbor" pages "(train-set)";
        trainFolds = toFolds "${name}-train" train;
      in {
           trainPackage = collectSymlinks {
             name = "benchmark-${name}-train";
             inputs = [
                 license
                 readme
                 (exportAll "${name}-train" train)
                 (exportTitles test)  (exportTopics test)
                 (exportTitles train) (exportTopics train)
               ] ++ map (exportAll "${name}-train") trainFolds;
           };
           testPackage = collectSymlinks {
             name = "benchmark-${name}-test";
             inputs = [ license readme (exportAll "${name}-test" test) (exportTopics test) ];
           };
           testPublicPackage = collectSymlinks {
             name = "benchmark-${name}-test-public";
             inputs = [ license readme (exportAll "${name}-test" test) (exportTopics test) ];
             include = [ "*.outlines" "*.titles" "*.topics" ];
           };
         };
  benchmarks = name: titleList:
     collectSymlinks {
       name = "benchmark-${name}";
       inputs = builtins.attrValues (benchmarkPackages name titleList);
     };

  # Everything
  all = collectSymlinks {
    name = config.productName;
    inputs =
         [] #builtins.attrValues carTools
      ++ [
        (pagesTocFile rawPages)
        (pagesTocFile articles)
        (pagesTocFile unprocessedTrain)
        (pagesTocFile unprocessedAll)
        (pagesTocFile redirectedPages)
        paragraphCorpus
        trainArchive
        (benchmarks "test200" ./test200.titles)
        (benchmarks "benchmarkY1" ./benchmarkY1.titles)
      ];
  };


  # Utilities
  export = mode: output: name: pagesFile:
    let toc = pagesTocFile pagesFile;
    in mkDerivation {
      name = "export-${mode}-${name}";
      buildInputs = [ toc ];
      buildCommand = ''
        mkdir $out
        ${carTools.export} ${toc}/pages.cbor --${mode} $out/${output}
      '';
    };
  exportParagraphs = export "paragraphs" "paragraphs.cbor";
  exportOutlines = export "outlines" "outlines.cbor";
  exportAll = name: pagesFile: collectSymlinks {
    name = "export-all";
    inputs = []; # TODO
  };

  exportTitles = pagesFile: mkDerivation {
    name = "export-titles";
    buildInputs = [pagesFile];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
      ${carTools.dump} titles ${pagesFile}/pages.cbor > $out/titles
    '';
  };

  exportTopics = pagesFile: mkDerivation {
    name = "export-topics";
    buildInputs = [pagesFile];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
      ${carTools.dump} sections --raw ${pagesFile}/pages.cbor > $out/topics
    '';
  };

  filterPages = name: pagesFile: pred: mkDerivation {
    name = "filter-${name}";
    buildInputs = [ pagesFile ];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
      ${carTools.filter} ${lang_filter_opts} ${pagesFile}/pages.cbor -o $out/pages.cbor '${pred}'
    '';
  };

  collectSymlinks = { name, inputs, include ? null }: mkDerivation {
    name = "collect-${name}";
    buildInputs = inputs;
    buildCommand =
      let
        copyInput = input:
          let outs = builtins.attrNames (builtins.readDir input.outPath);
          in if builtins.length outs == 0
             then ""
             else if builtins.length outs == 1
             then "ln -s ${input}/${builtins.elemAt outs 0} $out/${input.name}"
             else ''
               mkdir -p $out/${input.name}
               ln -s ${input}/* $out/${input.name}
             '';
      in ''
      mkdir $out
      ${pkgs.lib.concatMapStringsSep "\n" copyInput inputs}
    '';
  };

  buildArchive = name: deriv: mkDerivation {
    name = "archive-${name}";
    buildInputs = [
      deriv
    ];
    nativeBuildInputs = [pkgs.zip];
    buildCommand = ''
      mkdir $out
      zip $out/out.zip $buildInputs
    '';
  };
}
