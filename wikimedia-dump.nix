{ stdenv, lib, fetchurl, wget, collectSymlinks,
  config, globalConfig }:

let
  root_url = "${config.mirror_url}${config.wiki_name}/${globalConfig.dump_date}";

  dumpsLocal = stdenv.mkDerivation {
    name = "dump-local";
    passthru.pathname = "dump-local";
    buildCommand = ''
      mkdir $out
      ln -s /home/ben/trec-car/data/enwiki-20161220/*.bz2 $out
    '';
  };

  # Dump file preparation
  dumpStatus = stdenv.mkDerivation rec {
    name = "dump-${config.wiki_name}-${globalConfig.dump_date}-status";
    passthru.pathname = name;
    src = config.dumpStatus;
    buildCommand = ''
      mkdir $out
      cp $src $out/dumpstatus.json
    '';
  };


  downloadOneDump = name: meta:
    let
      drvName = "dump-${config.wiki_name}-${globalConfig.dump_date}-${name}";
    in stdenv.mkDerivation {
        name = drvName;
        passthru.pathname = drvName;
        src = fetchurl {
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

  collectDumps = dumps: 
    collectSymlinks rec {
      name = "dump-${config.wiki_name}-${globalConfig.dump_date}";
      pathname = name;
      inputs = dumps;
    };
in
{
  dumpsDownloadedTest =
    collectDumps 
      (lib.take 2 (lib.mapAttrsToList downloadOneDump metadata.jobs.articlesdump.files));

  dumpsDownloaded =
    collectDumps 
      (lib.mapAttrsToList downloadOneDump metadata.jobs.articlesdump.files);

  dumpsOld = stdenv.mkDerivation rec {
    name = "dump-${config.wiki_name}-${globalConfig.dump_date}";
    passthru.pathname = name;
    buildInputs = [ wget ];
    buildCommand = ''
      mkdir $out
	    wget --directory-prefix $out -nd -c -r --no-parent --accept '*-pages-articles[0-9]*.bz2' ${root_url} || test $? = 8
	    #wget --directory-prefix $out -nd -c -r --no-parent --accept '*-pages-articles1.*.bz2' ${root_url} || test $? = 8
    '';
  };
}
