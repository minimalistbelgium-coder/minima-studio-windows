# Moteur de dérush (Minima Studio)

Fonctionne sans internet, sur Mac et Windows. Il est appelé par l'app Minima Studio.

1. `scan <dossier>` : repère les caméras (un sous-dossier par caméra) et les micros, et coche les micros qui servent.
2. `run <config.json>` : synchronise les caméras sur les micros (avec correction de dérive), détecte qui parle,
   fait le découpage multicam et écrit `<nom>.xml` + `<nom>.minima.json` dans le dossier de l'épisode.
3. L'app ouvre le XML dans Premiere, on l'enregistre puis on le ferme.
4. `finalize <projet.prproj> <nom>.minima.json` : active le multicam (chaque plan sur la bonne caméra) et coupe
   le micro de la personne qui écoute. Une copie `.avant-minima` du projet est gardée.

Le projet contient 3 séquences : SYNCRO, MULTICAM (source) et MONTAGE.
