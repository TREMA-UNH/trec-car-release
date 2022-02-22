./run.sh main --cores 30 --max-jobs 4 --arg configFile ./config.${1}.nix
pushd result-main
tar -chvf /home/ben/trec-car/data/wiki2022-${1}-unprocessedAllJsonl.tar unprocessedAllJsonl/*
tar -chvf /home/ben/trec-car/data/wiki2022-${1}-unprocessedAllCbor.tar unprocessedAllCbor/*
tar -chvf /home/ben/trec-car/data/wiki2022-${1}-collectionCbor.tar collectionCbor/*
tar -chvf /home/ben/trec-car/data/wiki2022-${1}-collectionJsonl.tar collectionJsonl/* 
popd

pxz /home/ben/trec-car/data/wiki2022-${1}-unprocessedAllJsonl.tar &
pxz /home/ben/trec-car/data/wiki2022-${1}-unprocessedAllCbor.tar &
pxz /home/ben/trec-car/data/wiki2022-${1}-collectionCbor.tar &
pxz /home/ben/trec-car/data/wiki2022-${1}-collectionJsonl.tar &


