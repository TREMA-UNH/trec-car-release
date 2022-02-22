cd main
tar -chvf /home/ben/trec-car/data/wiki2022-${1}-unprocessedAllJsonl.tar unprocessedAllJsonl/*
tar -chvf /home/ben/trec-car/data/wiki2022-${1}-unprocessedAllCbor.tar unprocessedAllCbor/*
tar -chvf /home/ben/trec-car/data/wiki2022-${1}-collectionCbor.tar collectionCbor/*
tar -chvf /home/ben/trec-car/data/wiki2022-${1}-collectionJsonl.tar collectionJsonl/* 

