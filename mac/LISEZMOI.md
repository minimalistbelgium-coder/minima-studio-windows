# Minima Studio 0.4

## Installer cette version sur ton Mac

Dans le Terminal :

    cd ~/Downloads/MinimaStudioMac && ./release.sh 0.4.0

Le script compile l'app, la signe, l'installe dans Applications et crée deux fichiers dans le dossier build :
- MinimaStudio-0.4.0.zip : la mise à jour, à publier depuis l'app
- MinimaStudio-0.4.0.dmg : l'installeur à envoyer aux monteurs

Au premier lancement, autorise Minima Studio dans Réglages Système > Confidentialité et sécurité > Accessibilité (bouton « Autoriser » dans la barre latérale). C'est ce qui permet de voir quel projet est ouvert dans Premiere.

## Signature Apple (à faire une seule fois)

Sans ça, macOS bloque l'app chez tes monteurs (« développeur non identifié ») et redemande l'autorisation Accessibilité à chaque version.

1. Certificat : Xcode > Réglages > Comptes > ton Apple ID > Gérer les certificats > + > « Developer ID Application ».
2. Mot de passe pour app : sur account.apple.com > Connexion et sécurité > Mots de passe pour app, crée-en un nommé « notarisation ».
3. Ton Team ID : developer.apple.com/account > Adhésion (10 caractères).
4. Dans le Terminal (remplace les deux valeurs, le mot de passe te sera demandé) :

       xcrun notarytool store-credentials minima --apple-id TON_APPLE_ID --team-id TON_TEAM_ID

Ensuite release.sh signe et fait valider (notariser) l'app et le .dmg par Apple automatiquement.

## Publier une mise à jour

1. ./release.sh 0.4.0 (toujours un numéro plus grand que le précédent)
2. Minima Studio > Mises à jour > choisis build/MinimaStudio-0.4.0.zip > Publier
3. Chez les autres, un bandeau « Nouvelle version disponible » apparaît. Un clic, l'app se remplace et se relance.

La page Mises à jour donne aussi un lien fixe vers le dernier .dmg, à envoyer à un nouveau monteur.

## Ajouter un monteur

1. Équipe > son adresse Gmail > rôle Monteur.
2. Tant que l'app Google est en mode test, ajoute aussi son adresse dans Google Cloud > Google Auth Platform > Audience > Utilisateurs test.
3. Il installe le .dmg, se connecte avec Google et autorise l'Accessibilité.

## Règles du chrono

- Il tourne quand Premiere est au premier plan avec un projet lié à une mission. Le projet est reconnu par son nom de fichier, où qu'il soit (Mac ou disque externe).
- Projet inconnu : l'app propose de l'associer à une mission. Le lien vaut pour toute l'équipe.
- 3 min sans clavier ni souris : pause, et ces 3 min sont retirées.
- Premiere n'est plus au premier plan : pause immédiate.
- Sortie de Premiere : les 2 premières minutes comptent. Au-delà, pause et question « Tu travailles toujours dessus ? ». Oui : le temps est compté. Non : il est retiré. Sans réponse en 15 min, la session se termine.
- Mise en veille ou verrouillage du Mac : la session se termine.
- Bouton « Démarrer le chrono » dans une mission pour compter du temps hors Premiere.
- Mode mini (⇧⌘M) : petite fenêtre toujours visible avec le chrono et le montant.

## Nouveautés 0.3

- Tu peux te cocher « Je monte moi-même ». Seul sur une mission : 100 % du budget, sans pondération. À plusieurs : ton temps compte ×1,5.
- Le monteur voit le budget max de chaque mission (liste, fiche, mini fenêtre).
- Le monteur indique où il en est (en montage, V1 livrée, corrections livrées). Tu reçois une notification et tu choisis de prévenir le client ou non.
- Fiche mission : bloc Rushes + bloc « Déposer mon montage » (lien WeTransfer commun, modifiable par l'admin).
- Bouton rouge : la fenêtre se cache, un clic sur l'icône du Dock la rouvre (ou ⌘0).
- Menu « … » en bas de la barre latérale : « Ouvrir au démarrage du Mac ».

## Nouveautés 0.4

- App universelle : le script refuse de publier si l'app ne tourne pas aussi sur Mac Intel.
- Sur un Mac Intel qui avait une ancienne version : réinstaller une fois depuis le .dmg (la mise à jour automatique ne peut pas démarrer sur une app qui ne s'ouvre pas).
- Onglet Séries supprimé.
- Tableau de bord admin et monteur, fiche mission, missions : design de la maquette, agenda de la semaine.
- Onglet Finances pour les monteurs : récap du mois, montant à facturer, rentabilité (€/h), bouton « Copier le récap ».
- Mode mini déplaçable (la position est mémorisée) : chrono, montant à la clé, ratio €/h.
- Notifications : bannières même quand l'app est ouverte, et alertes automatiques (nouvelle mission, statut, rushes, deadline, brief, début de session).
- Fenêtre plus petite possible, barre latérale réduite en icônes quand la fenêtre est étroite.
- Mises à jour : les anciennes versions sont supprimées à chaque publication.
