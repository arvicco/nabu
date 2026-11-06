# Requête pour constituer un sous-corpus

Afin de créer rapidement un sous-corpus à partir de la collection [Mazarinades](https://github.com/Antonomaz/Corpus/tree/main/Mazarinades), il vous suffit de suivre les étapes suivantes :

* Cloner, si ce n'est pas déjà fait, ce dépôt avec :
```bash
git clone https://github.com/Antonomaz/Corpus.git
```

* Ouvrir le projet [`Antonomaz.xpr`](https://github.com/Antonomaz/Corpus/blob/main/Antonomaz.xpr) avec le logiciel Oxygen.

* Dans la barre de recherche XPath (en haut à gauche), assurez-vous que le projet entier est concerné par votre recherche. Pour modifier cela, cliquez sur la petite icône à gauche de la barre de recherche et sélectionnez `Projet`.

* Préciser ensuite la requête qui vous intéresse. En voici quelques exemples :
  - Tous les textes de type burlesque : `.//keywords/term[@type='genre']/contains(., 'burlesque')`
  - Tous les textes contenant uniquement des vers : `.//keywords/term[@type='form']/contains(., 'vers')`
  - Tous les textes de type satirique : `.//keywords/term[@type='genre']/contains(., 'satirique')`

* Les résultats de votre requêtes s'afficheront en bas de votre écran : vous pouvez sélectionner tous les résultats positifs et, avec un clic droit, ouvrir les fichiers ou en copier les identifiants.