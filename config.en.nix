{ pkgs }:

{
  config = rec {
    productName = "trec-car";
    lang = "en";
    wiki_name = "${lang}wiki";
    mirror_url = http://dumps.wikimedia.your.org/;
    import_config = ./config.en.yaml;
    dumpStatus = ./dumpstatus.json;

    # if lost, ressurect from here: jelly:/mnt/grapes/datasets/trec-car/duplicates.v1.5-table.xz
    # duplicates-prev-table = /home/ben/trec-car/data/enwiki-20161220/release-v1.5/articles.dedup.cbor.duplicates.table;

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


    filterPagesWithPrefix = ''
      name-has-prefix "Category:" |
      name-has-prefix "Portal:" |
      name-has-prefix "List of " |
      name-has-prefix "Lists of "
    '';

    carFilterCategories = ''
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

    filterPredicates = " !is-disambiguation";

    benchmarkY1titles = ./benchmarkY1.titles;
    test200titles = ./test200.titles;

    # For 01/01/2022 only very few articles are tagges with "Vital Article" instead we:
    # Create a list of vital pages created with wikidata sparql query
    # SELECT ?item {?item wdt:P5008 wd:Q5460604 . OPTIONAL {?item wikibase:sitelinks ?sl } . OPTIONAL {?item wikibase:statements ?st } } ORDER BY ?item
    # using https://query.wikidata.org/
    vitalArticleQids = ./vital-articles.qids;

    # type BenchmarkDef = { name :: String, titleList :: String, predicate :: String }
    # benchmarks :: List BenchmarkDef
    benchmarks = [
      {name = "benchmarkY1";
       predicate = "name-or-redirect-set-from-file \"${benchmarkY1titles}\"";
      }
      {name = "test200";
       predicate = "name-or-redirect-set-from-file \"${test200titles}\"";
     }
     { name = "vital-articles";
      predicate = "qid-set-from-file \"${vitalArticleQids}\"";
    }
     { name = "good-articles";
       predicate = "has-page-tag [\"Good article\"]";
     }
     { name = "US-history";
      predicate = "( category-contains \" history\" & category-contains \" united states\" )";
    }
    { name = "car-train-large";
      predicate = "( train-set ) & (! ${carFilterCategories} )";
    }
   ];

    butBenchmarkPredicate = "((! name-or-redirect-set-from-file  \"${test200titles}\") & (! name-or-redirect-set-from-file \"${benchmarkY1titles}\") )";
  };

  globalConfig = rec {
    version = "v2.6";
    dump_date = "20220101";
    wikidata_dump_date = "20220103";
    wikidata_dump_sha256 = "1dzxm740gm74wnb96bb8829gygkmqwwpzihbrljzrddr74hfpnch";
    lang_index = "lang-index";
    dropPagesWithPrefix = ''
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
  };
}
