{ pkgs }:

{
  config = rec {
    productName = "trec-car";
    lang = "ja";
    wiki_name = "${lang}wiki";
    mirror_url = http://dumps.wikimedia.your.org/;
    import_config = ./config.ja.yaml;

    forbiddenHeadings = pkgs.lib.concatMapStringsSep " " (s: "--forbidden '${s}'") [
      "see also"
      "関連項目"
      "references"
      "参考文献"
      "external links"
      "外部リンク"
      "notes"
      "脚注"
      "注釈"
      "bibliography"
      "略歴"
      "gallery"
      "ギャラリー"
      "publications"
      "著作"
      "further reading"
      "読書案内"
      "track listing"
      "収録曲"
      "sources"
      "出典"
      "cast"
      "出演"
      "discography"
      "ディスコグラフィ"
      "awards"
      "表彰"
      "other"
      "その他"
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
      name-has-prefix "特別:" |
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
      name-has-prefix "Lists of " |
      name-has-suffix "一覧" |
      name-has-suffix "年表"
    '';
    categoryPreds = ''
      category-contains " births" |
      category-contains "誕生" |
      category-contains "deaths" |
      category-contains "死亡した人物" |
      category-contains " people" |
      category-contains "人物" |
      category-contains " event" |
      category-contains "イベント" |
      category-contains " novels" |
      category-contains "小説" |
      category-contains " novel series" |
      category-contains "小説シリーズ" |
      category-contains " books" |
      category-contains "書物" |
      category-contains " fiction" |
      category-contains "フィクション" |
      category-contains " plays" |
      category-contains "戯曲" |
      category-contains " films" |
      category-contains "映画作品" |
      category-contains " awards" |
      category-contains "表彰" |
      category-contains " television series" |
      category-contains "テレビ番組のシリーズ" |
      category-contains " musicals" |
      category-contains "ミュージカル作品" |
      category-contains " songs" |
      category-contains "の歌" |
      category-contains "の楽曲" |
      category-contains " singers" |
      category-contains "歌手" |
      category-contains " artists" |
      category-contains "芸術家" |
      category-contains "アーティスト" |
      category-contains " music groups" |
      category-contains " musical groups" |
      category-contains "音楽グループ" |
      category-contains " discographies" |
      category-contains "ディスコグラフィ" |
      category-contains " concert tours" |
      category-contains "コンサート・ツアー" |
      category-contains " albums" |
      category-contains "アルバム" |
      category-contains " soundtracks" |
      category-contains "サウンドトラック" |
      category-contains " athletics clubs" |
      category-contains "football clubs" |
      category-contains "サッカークラブ" |
      category-contains " competitions" |
      category-contains "競技会" |
      category-contains " leagues" |
      category-contains " リーグ" |
      category-contains " national register of historic places listings in " |
      category-contains "文化遺産保護制度" |
      category-contains " by country" |
      category-contains "国別" |
      category-contains " by year" |
      category-contains "年別" |
      category-contains "年度別" |
      category-contains "years in " |
      category-contains "years of the " |
      category-contains "年表" |
      category-contains "lists of " |
      category-contains "一覧" 
    '';
  };
}

