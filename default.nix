{ configFile, dumpTest ? false, deduplicate ? false, exportJsonlGz ? false, exportCbor ? true, exportJsonlSplits ? true, exportFull ? true }:

let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs { };
  inherit (pkgs) lib;
  inherit (pkgs.stdenv) mkDerivation;
  # unionAttrs :: List Attrset -> Attrset
  unionAttrs = xs: lib.foldr (a: b: a // b) {} xs;
  replaceString = needle: subst: haystack: lib.replaceStrings [needle] [subst] haystack;

  symlink-tree = import ./symlink-tree.nix { inherit (pkgs) stdenv lib; };
  symlinkDrv = drv:
    let xs = lib.attrNames (builtins.readDir drv);
    in if builtins.length xs == 1
      then { "${drv.pathname}" = symlink-tree.file "${drv}/${lib.elemAt xs 0}"; }
      else throw "symlinkDrv: Multiple files in ${drv}";

  symlinkDirDrv = drv:
      { "${drv.pathname}" = symlink-tree.symlink "${drv}"; };

  config = (import configFile { inherit pkgs; }).config;
  globalConfig = (import configFile { inherit pkgs; }).globalConfig;

  out_dir = "output/${config.productName}";

  carToolNames = {
    build_toc         = "trec-car-build-toc";
    filter            = "trec-car-filter";
    export            = "trec-car-export";
    _import           = "trec-car-import";
    cat               = "trec-car-cat";
    dump              = "trec-car-dump";
    fill_metadata     = "trec-car-fill-metadata";
    transform_content = "trec-car-transform-content";
    trec-car-minhash-duplicates = "trec-car-minhash-duplicates";
    trec-car-rewrite-duplicates = "trec-car-rewrite-duplicates";
    trec-car-duplicates-rewrite-table = "trec-car-duplicates-rewrite-table";
    cross-site        = "trec-car-cross-site";
    jsonl-export       = "trec-car-jsonl-export";
    jsonl-split        = "trec-car-split-jsonl";
    jsonl-provenance   = "trec-car-jsonl-provenance";
    export-cluster-benchmark = "trec-car-cluster-benchmark";
  };
  carTool = name: ./car-tools + "/${name}";
  carTools = lib.mapAttrs (_: carTool) carToolNames;


in rec {
  inherit carTools lib;
  defExportCfg = { exportJsonlGz = exportJsonlGz; exportCbor = exportCbor; exportJsonlSplits = exportJsonlSplits; exportFull = exportFull; };

  carToolFiles = lib.concatStringsSep "\n" (lib.attrValues carToolNames);


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
      ${carTools.build_toc} page-qids $out/pages.cbor
    '';
  };

  parasTocFile = parasFile: mkDerivation rec {
    name = "${parasFile}.toc";
    passthru.pathname = name;
    buildInputs = parasFile;
    buildCommand = '' ${carTools.build_toc} paragraphs ${parasFile} > $out '';
  };

  dumps = 
    let dumpDerivs  = pkgs.callPackage ./wikimedia-dump.nix { inherit config globalConfig collectSymlinks; };
    in if dumpTest then dumpDerivs.dumpsDownloadedTest else dumpDerivs.dumpsDownloaded;

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


  # 0. all: Import
  rawPages =
    let
      dumpFiles = builtins.attrNames (builtins.readDir dumps.out);
      genRawPages = dumpFile: mkDerivation {
        name = "rawPagesSingle";
        passthru.pathname = "${dumpFile}-rawPages.cbor";
        buildCommand = ''
          mkdir $out
          bzcat ${dumpFile} | ${carTools._import} -c ${config.import_config} --dump-date=${globalConfig.dump_date} --release-name="${config.productName} ${globalConfig.version}" -j$NIX_BUILD_CORES > $out/pages.cbor
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
  contentPages = filterPages "content.cbor" rawPages '' (!(${globalConfig.dropPagesWithPrefix})) '' "content.cbor";

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

  disambiguatedPages = fixDisambig redirectedPages;

  # 0.7: Fill WikiData QID
  wikiDataDump = mkDerivation {
    name = "wikiDataDump";
    passthru.pathname = "wiki-data-dump.json.bz2";
    # option for downloading
    src = pkgs.fetchurl {
      url =
        let
          #mirror = "http://dumps.wikimedia.your.org";
          mirror = "https://dumps.wikimedia.org";
        in "${mirror}/wikidatawiki/entities/${globalConfig.wikidata_dump_date}/wikidata-${globalConfig.wikidata_dump_date}-all.json.bz2";
      sha256 = globalConfig.wikidata_dump_sha256;
    };
    #src = builtins.fetchurl {
    #  url = "file:///home/ben/trec-car/data/wiki2022/wikidata-20211220-all.json.bz2";
    #  sha256 = "0fdbzfyxwdj0kv8gdv5p0pzng4v4mr6j40v8z86ggnzrqxisw72a";
    #};
    buildCommand = ''
      mkdir $out
      # mv $src $out/wiki-data-dump.json.bz2
      ln -s $src $out/wiki-data-dump.json.bz2
    '';
  };

  wikiDataCrossSite = mkDerivation {
    name = "wiki-data-cross-site";
    passthru.pathname = "cross-site.cbor";
    buildInputs = [ wikiDataDump ];
    buildCommand = ''
      mkdir $out
      ${carTools.cross-site} -i ${wikiDataDump}/wiki-data-dump.json.bz2 -o $out/cross-site.cbor +RTS -N$NIX_BUILD_CORES -A128M -s -qn4
    '';
  };

  pagesWithQids = pages: mkDerivation {
    name = "pages-with-qids.cbor";
    passthru.pathname = "pages-with-metadata.cbor";
    buildInputs = [ pages ];
    buildCommand = ''
      mkdir $out
      ${carTools.fill_metadata} --qid -i ${pages}/pages.cbor -o $out/pages.cbor --wikidata-cross-site ${wikiDataCrossSite}/cross-site.cbor --siteId ${config.wiki_name}
    '';
  };

  jsonlExport = {pages, output ? "pages.cbor" }: mkDerivation {
    name = "jsonl-export";
    passthru.pathname = "${replaceString ".cbor" "" pages.pathname}.jsonl.gz";
    outname = "car.jsonl.gz";
    buildCommand = ''
      mkdir $out
      ${carTools.jsonl-export} -o $out/$outname  ${pages}/${output}
      '';
  };



  jsonlProvExport = {pages, output ? "pages.cbor" }: mkDerivation {
    name = "jsonl-prov-export";
    passthru.pathname = "${replaceString ".cbor" "" pages.pathname}.provenance.jsonl";
    outname = "car.prov.jsonl";
    buildCommand = ''
      mkdir $out
      ${carTools.jsonl-provenance} -o $out/$outname  ${pages}/${output}
      '';
  };



  jsonlSplit = fileType: jsonl : mkDerivation {
    name = "jsonl-split";
    passthru.pathname = replaceString ".jsonl.gz" ".jsonl-splits" jsonl.pathname;
    buildCommand = 
      let num = if (fileType == "paragraphs") then "1000000" else "100000";
      in 
      ''
      mkdir $out
      ${carTools.jsonl-split} -n ${num} -o $out/${fileType}-{n}.jsonl.gz ${jsonl}/${jsonl.outname}
      '';
  };

  unprocessedAll = pagesWithQids disambiguatedPages;

  # todo: fix order of definition (articles is defined below)
  unprocessedTrain = filterPages "unprocessed-trainLarge" articles "(train-set)" "unprocessedTrain.cbor";
  unprocessedTrainPackage = cfg: pageFoldsPackages ({ pages = unprocessedTrain; name = "unprocessedTrainLarge";} // cfg);
  unprocessedAllPackage = cfg: pagesPackages ({pages = unprocessedAll; name = "unprocessedAll";} // cfg);
  
  test200titles=./test200.titles;
  benchmarkY1titles=./benchmarkY1.titles;


  test200RedirectedTitles = redirectedTitles {pages = articles; titles = test200titles;};


  # 1. Drop non-article pages
  articles =
    filterPages "articles" unprocessedAll "(!is-redirect & !is-disambiguation & !is-category)" "articles.cbor";

  articlesWithToc = pagesTocFile articles;
  
  unprocessedAllButBenchmark = 
   filterPages "allbutbenchmark" articles "${config.butBenchmarkPredicate}" "unprocessedAllButBenchmark.cbor";
  unprocessedAllButBenchmarkPackage = cfg: pageFoldsPackages ({pages = unprocessedAllButBenchmark; name = "unprocessedAllButBenchmark";} // cfg);
  unprocessedAllButBenchmarkArchive = cfg: buildArchive "unprocessedAllButBenchmark" (unprocessedAllButBenchmarkPackage cfg);


  unprocessedPackage = cfg: symlink-tree.mkSymlinkTree {
    name = "unprocessedPackage";
    components = symlink-tree.directory ({}
    // symlinkDrv  (buildArchive "unprocessedAllButBenchmark" (unprocessedAllButBenchmarkPackage cfg))
    // symlinkDrv  (buildArchive "unprocessedTrain" (unprocessedTrainPackage cfg))
    // symlinkDrv  (buildArchive "unprocessedAll" (unprocessedAllPackage cfg))
    );
  };

  importDumpDebug = symlink-tree.mkSymlinkTree {
    name = "importDebugDebug";
    components =
      let
         toc = name: drv: {
          "${name}.cbor.toc" = symlink-tree.file "${drv}/pages.cbor.toc";
          "${name}.cbor" = symlink-tree.file "${drv}/pages.cbor";
        };
      in symlink-tree.directory ({}
      // toc "raw" (pagesTocFile rawPages)
      // toc "articles" (pagesTocFile articles)
      // toc "content" (pagesTocFile contentPages)
      // toc "unprocessed-all" (pagesTocFile unprocessedAll)
      // toc "redirected" (pagesTocFile redirectedPages)
      // toc "disambiguated" (pagesTocFile disambiguatedPages)
      );
  };
  

  # 2. Drop aministrative headings and category links
  processedArticles =
    let
      transformUnproc = "${config.pageProcessing}"; #"--lead --image --shortHeading --longHeading --shortpage ${config.forbiddenHeadings}";
    in mkDerivation {
      name = "proc.articles.cbor";
      passthru.pathname = "car.cbor";
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

      deduped = mkDerivation {
        name = "dedup.articles.cbor";
        passthru.pathname = "car-deduplicate.cbor";
        buildInputs = [processedArticles duplicatesTable];
        buildCommand = ''
          mkdir $out
          ${carTools.trec-car-rewrite-duplicates} -o $out/pages.cbor -d ${duplicatesTable}/duplicates.table ${processedArticles}/pages.cbor
        '';
      };
    in if deduplicate then deduped else processedArticles;

  # 3e. export deduplication data
  deduplicationPackage = symlink-tree.mkSymlinkTree {
    name = "deduplication-package";
    components = symlink-tree.directory (unionAttrs (map symlinkDrv ([duplicatesTable] ++ duplicateMappings)));
  };



  # ** Paragraph Corpus
  paragraphCorpus = exportParagraphs "paragraph-corpus" dedupArticles;

  paragraphCorpusPackage  = { exportJsonlGz, exportCbor, exportJsonlSplits, exportFull} :
    symlink-tree.mkSymlinkTree {
    name = "paragraphCorpus";
    components = 
    let paragraphJsonl = jsonlExport { pages = paragraphCorpus; output = "paragraphs.cbor";};
        paragraphProvJsonl = jsonlProvExport { pages = paragraphCorpus; output = "paragraphs.cbor";};
        paragraphsSplit = jsonlSplit "paragraphs" paragraphJsonl;
      in symlink-tree.directory( {}
        // symlinkDrv license
        // symlinkDrv readme
        // lib.attrsets.optionalAttrs exportCbor (symlinkDrv paragraphCorpus) 
        // lib.attrsets.optionalAttrs (exportJsonlGz || exportJsonlSplits) (symlinkDrv paragraphProvJsonl)
        // lib.attrsets.optionalAttrs exportJsonlGz (symlinkDrv paragraphJsonl)
        // lib.attrsets.optionalAttrs exportJsonlSplits
            { "${paragraphsSplit.pathname}" = symlink-tree.symlink paragraphsSplit ; }
    );
  };

  paragraphCorpusArchive = cfg: buildArchive "paragraphCorpus" (paragraphCorpusPackage cfg);

  # 3. Drop pages of forbidden categories
  filtered =
    let
      preds = '' (!(${globalConfig.dropPagesWithPrefix}) & ${config.filterPredicates}) '';
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
  baseTrainAllFolds = symlink-tree.mkSymlinkTree {
    name = "base-train-folds"; 
    components = symlink-tree.directory ({} 
       // symlinkDrv baseTrainFolds
    );
  };

  # Readme
  readme = mkDerivation {
    name = "README.mkd";
    passthru.pathname = "README.mkd";
    nativeBuildInputs = [pkgs.git];
    buildCommand = ''
      mkdir $out
      cat <<EOF >$out/README.mkd
      # TREC CAR ${globalConfig.version}

      This data set is part of the TREC CAR dataset version ${globalConfig.version}.

      The included TREC CAR data sets by Laura Dietz, Ben Gamari available
      at `trec-car.cs.unh.edu` are provided under a <a rel="license"
      href="http://creativecommons.org/licenses/by-sa/3.0/deed.en_US">Creative
      Commons Attribution-ShareAlike 3.0 Unported License</a>. The data is
      based on content extracted from <https://dumps.wikipedia.org/> that is
      licensed under the Creative Commons Attribution-ShareAlike 3.0 Unported
      License.

      trec-car-create:
        $(echo ${builtins.readFile ./car-tools/tools-commit})
        in git repos ${builtins.readFile ./car-tools/tools-remote}

      build system:
        $(git -C ${./.} rev-parse HEAD)
        in git repos $(git -C ${./.} remote get-url origin)
      EOF
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
  trainLargePackageCfg = cfg: (benchmarkPackages ({basePages = baseTrain; name = "train-large-package";} // cfg)).trainPackage;
  trainLargeArchive = cfg: buildArchive "train-large" (trainLargePackageCfg cfg);
  trainLargePackage = trainLargePackageCfg defExportCfg;

  # 9. Build benchmarks
  allExports2 = {name, pages, exportJsonlGz, exportCbor, exportJsonlSplits, exportFull}:
      let cfg = { inherit exportJsonlGz exportCbor exportJsonlSplits exportFull;};
          outlines = (exportOutlines "${name}-outlines" pages);
          paragraphs = (exportParagraphs "${name}-paragraph" pages);
          pagesJsonl = (jsonlExport { pages = pages ; } ); 
          outlinesJsonl = (jsonlExport { pages = outlines ; output = "outlines.cbor"; } );
          paragraphsJsonl = (jsonlExport { pages = paragraphs ; output = "paragraphs.cbor"; });
          pagesSplit = jsonlSplit "pages" pagesJsonl;
          outlinesSplit = jsonlSplit "outlines" outlinesJsonl;
          paragraphsSplit = jsonlSplit "paragraphs" paragraphsJsonl;
          pagesProvenance = jsonlProvExport { pages = pages ; }; 
      in unionAttrs (map symlinkDrv (
        (lib.optionals exportCbor [paragraphs outlines])
        ++ [
        (exportQrel "para-hier-qrel"     "hierarchical" name pages)
        (exportQrel "para-article-qrel"  "article" name pages)
        (exportQrel "para-toplevel-qrel" "toplevel" name pages)
        (exportQrel "entity-hier-qrel"     "hierarchical.entity" name pages)
        (exportQrel "entity-article-qrel"  "article.entity" name pages)
        (exportQrel "entity-toplevel-qrel" "toplevel.entity" name pages)
        (exportClusterBenchmark "para-toplevel-cluster" "toplevel.cluster" name pages)    
        (exportEntityLinkingBenchmark "entity-linking" name pages)
      ]++ (lib.optionals exportJsonlGz [
           pagesJsonl
           outlinesJsonl
           paragraphsJsonl
         ])
         ++ (lib.optionals (exportJsonlGz || exportJsonlSplits) [ pagesProvenance ])))
      // lib.attrsets.optionalAttrs exportJsonlSplits {
        "${pagesSplit.pathname}" = symlink-tree.symlink pagesSplit;
        "${outlinesSplit.pathname}" = symlink-tree.symlink outlinesSplit;
        "${paragraphsSplit.pathname}" = symlink-tree.symlink paragraphsSplit;
      };
      


  pageFoldsPackages = {pages, name, exportJsonlGz, exportCbor, exportJsonlSplits, exportFull}:
    let cfg = { inherit exportJsonlGz exportCbor exportJsonlSplits exportFull;};
     in symlink-tree.mkSymlinkTree {
      name = "${name}";
      components = 
        let jsonlAll = jsonlExport { pages = pages; };
            allFolds = toFolds "${name}" pages; 
            jsonlFolds = map (f: (jsonlExport { pages = f; })) allFolds;
            jsonlFoldSplits = map (f: (jsonlSplit "pages" f)) jsonlFolds;
            pagesProvenance = jsonlProvExport { pages = pages ; };
        in symlink-tree.directory ({}
          // symlinkDrv license
          // symlinkDrv readme
          // lib.attrsets.optionalAttrs (exportFull && exportCbor) (symlinkDrv pages)   # full CBOR
          // lib.attrsets.optionalAttrs (exportFull && exportJsonlGz)( symlinkDrv jsonlAll)  # full jsonl.gz
          // lib.attrsets.optionalAttrs (exportFull && exportJsonlSplits) ( 
             let spl =  jsonlSplit "pages" jsonlAll;   # full jsonl-splits
             in {"${spl.pathname}" = symlink-tree.symlink spl;}   # full jsonl-splits
          )
          // lib.attrsets.optionalAttrs exportCbor (
              unionAttrs (map (f: symlinkDrv f) allFolds)  # fold CBOR
             )
          // lib.attrsets.optionalAttrs (exportJsonlGz || exportJsonlSplits) (
              symlinkDrv pagesProvenance   # jsonl provenance
             )
          //  lib.attrsets.optionalAttrs exportJsonlGz ( 
            unionAttrs (map (f: symlinkDrv f) jsonlFolds)   # fold jsonl.gz
           )
          // lib.attrsets.optionalAttrs exportJsonlSplits (
              unionAttrs (map (f: {"${f.pathname}" = symlink-tree.symlink f; }) jsonlFoldSplits)  # fold jsonl-splits
           )
        );
      };

  pagesPackages = {pages, name, exportJsonlGz, exportCbor, exportJsonlSplits, exportFull}: 
    symlink-tree.mkSymlinkTree {
      name = "${name}";
      components = 
        let jsonlAll = (jsonlExport { pages = pages; });
        in symlink-tree.directory ({}
          // symlinkDrv license
          // symlinkDrv readme
          // lib.attrsets.optionalAttrs exportCbor (symlinkDrv pages)
          // lib.attrsets.optionalAttrs (exportJsonlGz || exportJsonlSplits) (symlinkDrv (jsonlProvExport { pages = pages ; }) )
          // lib.attrsets.optionalAttrs exportJsonlGz (symlinkDrv jsonlAll)
          // lib.attrsets.optionalAttrs exportJsonlSplits (
             let spl =  jsonlSplit "pages" jsonlAll;
             in {"${spl.pathname}" = symlink-tree.symlink spl;}
          )
        );
      };
      


  benchmarkPackages = {basePages, name, titleList ? null, predicate ? null, exportJsonlGz, exportCbor, exportJsonlSplits, exportFull}:
      let cfg = { inherit exportJsonlGz exportCbor exportJsonlSplits exportFull;};
      pages = if titleList != null 
                then filterPages "filtered-benchmark-${name}" basePages ''(name-or-redirect-set-from-file "${titleList}")'' "pages.cbor" 
                else if predicate != null
                  then filterPages "filtered-benchmark-${name}" basePages ''(${predicate})'' "pages.cbor" 
                  else basePages;

#      if (titleList == null  && predicates == null)
#                then basePages
#                else filterPages "filtered-benchmark-${name}" basePages ''(name-or-redirect-set-from-file "${titleList}")'' "pages.cbor" ;

        test  = filterPages "${name}-test.cbor" pages "(test-set)" "test.pages.cbor";
        train = filterPages "${name}-train.cbor" pages "(train-set)" "train.pages.cbor";
        trainFolds = toFolds "${name}-train" train;
        testFolds = toFolds "${name}-test" test;
      in {
        trainPackage = symlink-tree.mkSymlinkTree {
          name = "benchmark-${name}-train";
          components =
            symlink-tree.directory ({}  # with `a // b` we are overwriting attributes in a that are present in b
            // symlinkDrv license
            // symlinkDrv readme
            // lib.attrsets.optionalAttrs (exportFull && exportCbor) (symlinkDrv train)
            // symlinkDrv (exportTitles train)
            // symlinkDrv (exportTopics train)
            // symlinkDrv (exportWikidataQids train)
            // lib.attrsets.optionalAttrs exportCbor (unionAttrs (map symlinkDrv trainFolds))
            // unionAttrs (map (pagesFile: allExports2 ({name = pagesFile.name; pages = pagesFile; } // cfg )) trainFolds)
            // lib.attrsets.optionalAttrs exportFull (allExports2 ({name = train.name; pages = train;} // cfg))
          );
        };
        testPackage = symlink-tree.mkSymlinkTree {
          name = "benchmark-${name}-test";
          components =
            symlink-tree.directory ({}  # with `a // b` we are overwriting attributes in a that are present in b
            // symlinkDrv license
            // symlinkDrv readme
            // lib.attrsets.optionalAttrs (exportFull && exportCbor) (symlinkDrv test)
            // symlinkDrv (exportTitles test)
            // symlinkDrv (exportTopics test)
            // symlinkDrv (exportWikidataQids test) 
            // lib.attrsets.optionalAttrs exportCbor (unionAttrs (map symlinkDrv testFolds))
            // unionAttrs (map (pagesFile: allExports2 ({name = pagesFile.name; pages = pagesFile; } // cfg )) testFolds)
            // lib.attrsets.optionalAttrs exportFull (allExports2 ({name = test.name; pages = test;} // cfg))
            );
          };
        
        testPublicPackage = symlink-tree.mkSymlinkTree {
          name = "benchmark-${name}-test-public";
          components =
            let
              outlines = (exportOutlines "${name}-outlines" test);
              outlinesJsonl = (jsonlExport { pages = outlines ; output = "outlines.cbor"; } );
              outlinesSplit = jsonlSplit "outlines" outlinesJsonl;
            in symlink-tree.directory ({}  # with `a // b` we are overwriting attributes in a that are present in b
            // symlinkDrv license
            // symlinkDrv readme
            // symlinkDrv (exportTitles test)
            // symlinkDrv (exportTopics test)
            // symlinkDrv (exportWikidataQids test) 
            // lib.attrsets.optionalAttrs exportCbor (symlinkDrv outlines)
            // lib.attrsets.optionalAttrs exportJsonlGz (symlinkDrv outlinesJsonl)
            // lib.attrsets.optionalAttrs exportJsonlSplits 
                 { "${outlinesSplit.pathname}" = symlink-tree.symlink outlinesSplit; }
            );
          };
      };


  deduplicationArchive = cfg: buildArchive "deduplication" (deduplicationPackage);
  unprocessedTrainArchive = cfg: buildArchive "unprocessedTrain" (unprocessedTrainPackage cfg);
  unprocessedAllArchive = cfg: buildArchive "unprocessedAll" (unprocessedAllPackage cfg);
  unprocessedTrainToc = pagesTocFile unprocessedTrain;
  test200Package = cfg: benchmarkPackages ({basePages = base; name = "test200"; titleList = ./test200.titles;} // cfg);
  test200Archive = cfg: buildArchive "test200" (test200Package cfg).trainPackage;
  benchmarkY1Package = cfg: benchmarkPackages ({basePages = base; name = "benchmarkY1"; titleList = ./benchmarkY1.titles;} // cfg); 
  benchmarkY1trainArchive = cfg: buildArchive "benchmarkY1train" (benchmarkY1Package cfg).trainPackage;
  benchmarkY1testArchive = cfg: buildArchive "benchmarkY1test" (benchmarkY1Package cfg).testPackage;
  benchmarkY1testPublicArchive = cfg: buildArchive "benchmarkY1test.public" (benchmarkY1Package cfg).testPublicPackage;




  benchmarkArchive = {name, titleList ? null, qidList ? null, predicate ? null}:  
    let cfg = defExportCfg;
    benchmarkPkg = benchmarkPackages ({basePages = base; name = name; titleList = titleList; predicate = predicate;} // cfg);

    in symlink-tree.mkSymlinkTree {
      name = "${name}";
      components = 
        symlink-tree.directory ( 
        { 
         "${name}.train" = symlink-tree.symlink benchmarkPkg.trainPackage;
         "${name}.test" = symlink-tree.symlink benchmarkPkg.testPackage;
         "${name}.publicTest" = symlink-tree.symlink benchmarkPkg.testPublicPackage;
        }
       );
    };

  # customBenchmark :: AttrSet String BenchmarkDef -> Derivation
  customBenchmark = benchmarkDefList:
    symlink-tree.mkSymlinkTree {
      name = "customBenchmarks"; 
      components =
          symlink-tree.directory (
            lib.listToAttrs (map (b: lib.nameValuePair b.name (symlink-tree.symlink (benchmarkArchive b))) benchmarkDefList)
          );
  };

  customBenchmarkArchives = customBenchmark config.benchmarks;


  allBasePackages = symlink-tree.mkSymlinkTree {
    name = config.productName;
    components = 
      let cfg = defExportCfg;
      in symlink-tree.directory ( #unionAttrs ( map symlinkDrv 
      { 
       "rawPages"= symlink-tree.symlink  (pagesTocFile rawPages);
       "articles" = symlink-tree.symlink (pagesTocFile articles);
       "allParagraphs" = symlink-tree.symlink (allParagraphs);  # @laura paraTocFile
       "unprocessedTrain" = symlink-tree.symlink (pagesTocFile unprocessedTrain);
       "unprocessedAll" = symlink-tree.symlink (pagesTocFile unprocessedAll);
       "redirectedPages" = symlink-tree.symlink (pagesTocFile redirectedPages);
       "disambiguatedPages" = symlink-tree.symlink (pagesTocFile disambiguatedPages);
       "paragraphCorpusPackage" = symlink-tree.symlink (paragraphCorpusPackage cfg);
       "trainLargePackage" = symlink-tree.symlink (trainLargePackageCfg cfg);
       "benchmarks" =  symlink-tree.symlink (customBenchmarkArchives); 
       "unprocessedTrainPackage" = symlink-tree.symlink (unprocessedTrainPackage cfg);
       "unprocessedAllPackage" = symlink-tree.symlink (unprocessedAllPackage cfg);
       "unprocessedAllButBenchmarkPackage" = symlink-tree.symlink (unprocessedAllButBenchmarkPackage cfg);
      }
     // lib.optionalAttrs deduplicate (symlinkDrv deduplicationArchive)
     );
  };

  allTrecCarPackages = symlink-tree.mkSymlinkTree {
    name = config.productName;
    components = 
      let cfg = defExportCfg;
      in symlink-tree.directory ( #unionAttrs ( map symlinkDrv 
      { 
       "rawPages"= symlink-tree.symlink  (pagesTocFile rawPages);
       "articles" = symlink-tree.symlink (pagesTocFile articles);
       "allParagraphs" = symlink-tree.symlink (allParagraphs);  # @laura paraTocFile
       "unprocessedTrain" = symlink-tree.symlink (pagesTocFile unprocessedTrain);
       "unprocessedAll" = symlink-tree.symlink (pagesTocFile unprocessedAll);
       "redirectedPages" = symlink-tree.symlink (pagesTocFile redirectedPages);
       "disambiguatedPages" = symlink-tree.symlink (pagesTocFile disambiguatedPages);
       "paragraphCorpusPackage" = symlink-tree.symlink (paragraphCorpusPackage cfg);
       "trainLargePackage" = symlink-tree.symlink (trainLargePackageCfg cfg);
       "test200Packagetrain" = symlink-tree.symlink (test200Package cfg).trainPackage;
       "benchmarkY1.train" = symlink-tree.symlink (benchmarkY1Package cfg).trainPackage;
       "benchmarkY1.test" = symlink-tree.symlink (benchmarkY1Package cfg).testPackage;
       "benchmarkY1.publicTest" = symlink-tree.symlink (benchmarkY1Package cfg).testPublicPackage;
       "unprocessedTrainPackage" = symlink-tree.symlink (unprocessedTrainPackage cfg);
       "unprocessedAllPackage" = symlink-tree.symlink (unprocessedAllPackage cfg);
       "unprocessedAllButBenchmarkPackage" = symlink-tree.symlink (unprocessedAllButBenchmarkPackage cfg);
      }
     // lib.optionalAttrs deduplicate (symlinkDrv deduplicationArchive)
     );
  };

  dumpDetails = symlink-tree.mkSymlinkTree {
    name = "${config.productName}-all-detailed";
    components = 
      let cfg = defExportCfg;
      in symlink-tree.directory (
      unionAttrs (map symlinkDirDrv (
           [] #builtins.attrValues carTools
        ++ [
          (pagesTocFile rawPages)
          (pagesTocFile articles)
          (pagesTocFile unprocessedTrain)
          (pagesTocFile unprocessedAll)
          (pagesTocFile redirectedPages)
          (pagesTocFile disambiguatedPages)
        ] ++
          lib.optional deduplicate deduplicationArchive
        )));
  };

  collectionPackages = symlink-tree.mkSymlinkTree {
    name = config.productName;
    components = 
      let cfg = defExportCfg;
      in symlink-tree.directory ( #unionAttrs ( map symlinkDrv 
      { 
       "paragraphCorpusPackage" = symlink-tree.symlink (paragraphCorpusPackage cfg);
       "benchmarks" =  symlink-tree.symlink (customBenchmarkArchives); 
       "unprocessedAllButBenchmarkPackage" = symlink-tree.symlink (unprocessedAllButBenchmarkPackage cfg);
      }
     );
  };
  
  allPackages = symlink-tree.mkSymlinkTree {
    name = config.productName;
    components = 
      let cfg = defExportCfg;
      in symlink-tree.directory ( #unionAttrs ( map symlinkDrv 
      { 
       "unprocessedTrain" = symlink-tree.symlink (pagesTocFile unprocessedTrain);
       "paragraphCorpusPackage" = symlink-tree.symlink (paragraphCorpusPackage cfg);
       "benchmarks" =  symlink-tree.symlink (customBenchmarkArchives); 
       "unprocessedTrainPackage" = symlink-tree.symlink (unprocessedTrainPackage cfg);
       "unprocessedAllPackage" = symlink-tree.symlink (unprocessedAllPackage cfg);
       "unprocessedAllButBenchmarkPackage" = symlink-tree.symlink (unprocessedAllButBenchmarkPackage cfg);
      }
     );
  };


  all = symlink-tree.mkSymlinkTree {
    name = "${config.productName}-all";
    components = 
    let cfg = defExportCfg;
    in symlink-tree.directory (unionAttrs ( map symlinkDrv 
      [
        (paragraphCorpusArchive cfg)
        #(trainLargeArchive cfg)
        (unprocessedTrainArchive cfg)
        (unprocessedAllArchive cfg)
        (unprocessedAllButBenchmarkArchive cfg)
      ] 
      ) // 
      {"benchmarks" =  symlink-tree.symlink (customBenchmarkArchives);}
      );
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
  exportBenchmark = {mode, output, pathname ? output, name, pagesFile}:
    let toc = pagesTocFile pagesFile;
    in mkDerivation {
      name = "export-${mode}-${name}";
      buildInputs = [ toc ];
      passthru.pathname = pathname;
      buildCommand = ''
        mkdir $out
        ${carTools.export-cluster-benchmark} ${toc}/pages.cbor --${mode} $out/${output}
      '';
    };
  exportClusterBenchmark = mode: output: name: pagesFile:
    exportBenchmark {
      mode = mode;
      output = "${output}.para.toplevel.cluster.jsonl.gz";
      pathname = "${baseNameOf pagesFile.pathname}-${output}.jsonl.gz";
      name = "${name}-${mode}";
      pagesFile = pagesFile;
    };
  exportEntityLinkingBenchmark =  output: name: pagesFile:
    exportBenchmark {
      mode = "entity-linking";
      output = "${output}.entity-linking.jsonl.gz";
      pathname = "${baseNameOf pagesFile.pathname}-${output}.jsonl.gz";
      name = "${name}-entity-linking";
      pagesFile = pagesFile;
    };

  allExports = name: pagesFile:
      let outlines = (exportOutlines "${name}-outlines" pagesFile);
          paragraphs = (exportParagraphs "${name}-paragraph" pagesFile);
          pagesJsonl = (jsonlExport { pages = pagesFile ; } ); 
          outlinesJsonl = (jsonlExport { pages = outlines ; output = "outlines.cbor"; } );
          paragraphsJsonl = (jsonlExport { pages = paragraphs ; output = "paragraphs.cbor"; });

      in [
        paragraphs
        outlines
        (exportQrel "para-hier-qrel"     "hierarchical" name pagesFile)
        (exportQrel "para-article-qrel"  "article" name pagesFile)
        (exportQrel "para-toplevel-qrel" "toplevel" name pagesFile)
        (exportQrel "entity-hier-qrel"     "hierarchical.entity" name pagesFile)
        (exportQrel "entity-article-qrel"  "article.entity" name pagesFile)
        (exportQrel "entity-toplevel-qrel" "toplevel.entity" name pagesFile)
        (exportClusterBenchmark "para-toplevel-cluster" "toplevel.cluster" name pagesFile)
        (exportEntityLinkingBenchmark "entity-linking" name pagesFile) 
        pagesJsonl
        outlinesJsonl
        paragraphsJsonl
        (jsonlSplit "pages" pagesJsonl)
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
      ${carTools.dump} section-ids --raw ${pagesFile}/pages.cbor > $out/topics
    '';
  };

  exportWikidataQids = pagesFile: mkDerivation {
    name = "export-qids-${pagesFile.name}";
    passthru.pathname = "qids";
    nativeBuildInputs = [ pkgs.glibcLocales ];
    buildInputs = [pagesFile];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
      ${carTools.dump} page-qids  ${pagesFile}/pages.cbor > $out/qids
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
      ${carTools.filter} ${pagesFile}/pages.cbor -o $out/pages.cbor '${pred}'
    '';
  };


  redirectedTitles = {pages, titles}: mkDerivation {
    name = "redirectedTitles-${titles}";
    passthru.pathname = "$titles.redirected.titles";
    buildInputs = [pages];
    buildCommand = ''
      mkdir $out
      export LANG=en_US.UTF-8
      ${carTools.dump} titles --redirects-from-file ${titles} ${pages} > titles.txt
    '';
  };

  ##########################################################
  # Utilities  (independent of trec car)
  ##########################################################

/*
  collectSymlinks2 = { name, files }: mkDerivation {
    name = name;
    buildCommand =
      pkgs.lib.concatStringsSep "\n"
      (["mkdir $out"] ++ pkgs.lib.mapAttrsToList (fname: file: "ln -s ${file} $out/${fname}") files);
  };
*/
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
      cp -rs ${deriv}/* ${name}
      find -type d | xargs chmod ug+wx
      tar --dereference -cJf $out/out.tar.xz ${name}
    '';
  };

  # Prevent nix from evaluating derivations in a list in parallel
  sequentialize = derivs:
    let f = drv: rest: builtins.seq (builtins.readDir drv.outPath) ([drv] ++ rest);
    in lib.foldr f [] derivs;
}
