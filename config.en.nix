{
  config = rec {
    productName = "trec-car";
    lang = "ja";
    wiki_name = "${lang}wiki";
    mirror_url = http://dumps.wikimedia.your.org/;
    import_config = ./config.en.yaml;
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
}
