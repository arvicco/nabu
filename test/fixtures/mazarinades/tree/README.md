# Corpus - Antonomaz

Ce répertoire contient un corpus de mazarinades encodées en XML-TEI.

## Les données

Le corpus est consultable depuis le dossier [Mazarinades](https://github.com/Antonomaz/Corpus/tree/main/Mazarinades).


Les textes sont ajoutés au fur et à mesure de leur encodage.

### Organisation des fichiers

Les mazarinades sont classées selon l'identifiant qui leur a été attribué par Moreau ([à retrouver ici](http://antonomaz.huma-num.fr/tools/Biblio_Moreau.html)). Elles sont classées par centaines (de 1-101 à 4001-4101).

Ces dossiers sont complétées par les `Suppléments` identifiés par Moreau et les mazarinades identifiées par `Socard` et `Labadie`.

Le dossier `Bibliothèque_Mazarine` contient les documents qui n'ont pas été repérés par Moreau, Socard ou Labadie.

Si plusieurs exemplaires correspondant à un seul et même numéro Moreau ont été trouvés, ils sont placés dans le dossier `Doublons`, ils n'ont à priori pas été relus.

Enfin, les dossiers `to_do` et `temp_MAZ` correspondent à des dossiers de travail et contiennent des fichiers qui doivent être relus avant d'être ajoutés aux dossiers déjà évoqués.




## Validation

La bonne qualité et la cohérence de l'encodage des textes sont assurées par l'[ODD du projet](https://github.com/Antonomaz/ODD). Le schéma de validation ainsi que de la documentation y sont accessibles.

## Aperçu des données encodées

Il est possible d'avoir un aperçu des mazarinades et de leurs métadonnées en consultant [corpus.csv](https://github.com/Antonomaz/Corpus/tree/main/output/corpus.csv) produit automatiquement à partir de [ce script](https://github.com/Antonomaz/Corpus/tree/main/script/tei_to_csv.py).

## Licence

Les textes sont publiés sous la licence [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
