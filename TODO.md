# TODO — MultiBot Chatless

## Bugs / corrections à vérifier

* Il semble y'avoir une regression, quand je me déconnecte et reconnecte l'UI du groupe nblizzard n'est pas refresh les bots restent en inconne je suis obligé de faire un reload
* Quand je fais addclass bots on m'envoi que des bots level 1 même si je suis level 80
* Inventaire bridge : vérifier qu'il n'y a plus de limite visuelle ou logique à 16 emplacements.
* Recentrer les icônes des glyphes.
* Glyphes : affichage lent — côté serveur corrigé (`FindGlyphItemId` indexe désormais les items glyphes en une seule passe DB au lieu d'une requête par slot au premier affichage). Vérifier s'il reste une lenteur côté client (chargement item/tooltip).
* Quick Shaman / Quick Hunter : faire en sorte que la croix de fermeture reste à la même place quand on ferme la frame.
* Quick bars : ne pas faire apparaître les quick bars pour les joueurs humains.
* Raidus : rafraîchir correctement à l'ouverture et à la fermeture.
* Raidus : ajouter un bouton pour enlever les bots inconnus et les supprimer aussi des SavedVariables.
* Talents / glyphes : revoir `UI/MultiBotTalent`, car il y a eu des modifications dans le fichier `.conf` de MultiBot.
* Refaire uns passe pour que toutes les frames respectent le strata de la config.
* Retravailler la frame pvp stats qu'elle ressemble aux autres, et ajuster l'alignement du texte
* Faire une UI pour enchanter les objets à moins qu'on arrive à faire le bot caster le spell sur la fenêtre de trade.
* Refaire le layout de la frame pvp stats pour harmoniser avec les autres frames
* voire si on peux ajouter l'avancement de la quête d'un bot


## Informations bot
* Dans les frames métier ajout d'un bouton pour faire le bot acheter les composants manquants pour crafter l'item.
* Infos personnage : onglets style Blizzard pour compétences, réputations et monnaies.
 

## Inventaire Bot étendu
* Ajout d'un bouton Pour déposer des objets dans la banque du bot.
* Ajout d'une frame pour afficher le contenu de la banque du bot, avec un bouton pour retirer les objets de la banque.
* Ajout d'un bouton pour déposer des objets dans la banque de guilde.
* Ajout d'une frame pour afficher le contenu de la banque de guilde.

** TODO
* Afficher les sous de la guilde dans la frame BDG

## Frame Loot

* Tri intelligent des bots : afficher en haut les bots qui peuvent réellement utiliser l’objet selon classe, spé, type d’armure, arme, rôle.
* Filtre par rôle : boutons Tous, Tank, Heal, DPS, Caster, Mêlée, ou par classe.
* Suggestion automatique : préselectionner le bot le plus pertinent au lieu du premier candidat.
* Tooltip enrichi : survol du bot = classe, spé, rôle, niveau, équipement actuel comparable si l’addon connaît l’inventaire.
* Indicateur de pertinence : par exemple Excellent, Possible, Mauvais choix, avec couleur verte/orange/rouge.
* Avertissement avant erreur : confirmer si tu attribues une plaque à un mage, une arme inutilisable, ou un item épique à un bot non adapté.
* Bouton “Attribuer recommandé” : un seul clic pour donner l’objet au meilleur candidat.
* Historique des loots : petite liste “objet donné à X” pendant la session, utile en raid.
* Mémorisation des préférences : par exemple toujours donner tissu spell à tel bot, plaques tank à tel autre, etc.
* Masquer les bots non pertinents : option pour ne voir que ceux qui peuvent équiper/utiliser l’objet.
* Lien avec MultiBotInventoryFrame : clic droit sur un bot dans la dropdown = ouvrir son inventaire/équipement.
* Mode compact : pour les combats, n’afficher que icône item + nom + dropdown + bouton.
* Bouton refresh transformé en icône : garder la sécurité manuelle sans prendre autant de place.
* Attribution rapide par raccourcis : Alt+clic attribue au bot recommandé, Shift+clic ouvre détails.
* Debug discret : une option /mb lootdebug au lieu de spam chat permanent.

## Améliorations UI encore ouvertes

* Units : ajouter un champ de recherche par nom dans la liste des bots (la pagination a un
  compteur de page, mais pas de filtre texte).
* Uniformiser le template de la frame reward avec le style d'Itemus.
* Ajouter une option pour choisir la taille des icônes de la main bar et des Quick Shaman / Quick Hunter.
* Voir quelles autres options utiles peuvent être ajoutées à la frame options de MultiBot.
* Créer les traductions Ace3 pour les tooltips Quick Shaman / Quick Hunter, notamment `Show / Hide / Move Quick Shaman`.
* Finir les options de déplacement des boutons.
* Trouver un moyen de charger tous les skins des pets hunter.

## Loot / vendor / roll

* Remplacer dans le menu loot `Quest` et `Skill` par `Disenchant`, ou ajouter une vraie stratégie `quest` / `skill` côté playerbots.
* `roll` : manquant.
* `roll [item]` : manquant.
* `s *` : déjà présent côté addon, legacy whisper, pas encore bridge-first.
* `s vendor` : déjà présent côté addon inventaire, legacy whisper item par item, pas encore bridge-first.
* `open items` : déjà présent côté addon, legacy whisper.

## À reprendre plus tard

* Commandes par groupe pour `follow` et `attack`.
  * Les patches `RUN~ORDER` / `MultiBotGroupOrderUI.lua` ont été revert.
  * Reprendre seulement après validation manuelle exacte des commandes playerbots acceptées.
  * Tester d'abord en jeu :
    * `@tank attack`
    * `@group1 attack`
    * `@group1 follow`
    * `@group1 stay`
  * Commencer par une intégration addon-only minimale.
  * Ne pas réintroduire tout de suite un endpoint bridge générique.

## Fonctions déjà ajoutées / migrées

### Bridge / chatless

* Handshake bridge `HELLO` / `HELLO_ACK`.
* Liveness bridge `PING` / `PONG`.
* Roster / Units bridge-first.
* States bridge-first.
* Details / detail bot bridge-first.
* Stats simples bridge-first.
* PVP stats bridge-first.
* Inventory bridge-first.
* Inventory post-action refresh bridge-first.
* Spellbook bridge-first.
* Talents / sélection de specs bridge-first.
* Glyphes / Custom Glyphs bridge-first.
* Quêtes bridge-first :
  * incompleted ;
  * completed ;
  * all.
* Frames de quêtes `all`, `completed` et `incompleted` uniformisées avec fond interne sombre, marges cohérentes et bouton `Abandonner` par quête de bot.
* Outfits bridge-first.
* Character Info bridge-first.
* Réputations bridge-first dans la frame Infos personnage.
* Monnaies / emblèmes bridge-first dans la frame Infos personnage, avec argent du bot.
* Banque bot bridge-first avec consultation, dépôt et retrait.
* Banque de guilde bot bridge-first avec consultation, dépôt et retrait protégé par les droits de guilde.
* Layout des frames banque bot et BDG uniformisé avec fond interne sombre.
* Trainer bridge-first :
  * bouton `Trainer` ajouté dans l'EveryBar après `Outfits` ;
  * frame harmonisée avec les frames de quêtes ;
  * consultation des sorts apprenables depuis le trainer sélectionné ;
  * apprentissage d'un sort ou de tous les sorts via bridge.
* RTSC bridge-first (`RUN~RTSC` / `GET~RTSC`, repli chat uniquement bridge coupé) — voir `docs/rtsc.md` :
  * les 9 emplacements de position sont rendus depuis l'état serveur réel, plus depuis un pari optimiste au clic (l'emplacement ne se remplit qu'après le cast `aedm` réellement détecté) ;
  * persistance des positions enregistrées après le cast, via le flush `persist` du bridge (elles survivaient rarement à une reconnexion du bot) ;
  * fermer la barre envoie `cancel` et non plus `rtsc reset`, qui effaçait toutes les positions enregistrées et désapprenait le sort `aedm` du maître ;
  * `reset` déplacé sur Shift+clic droit du bouton racine, avec remise à zéro des 9 emplacements ;
  * nouvelles commandes exposées : mode `move` (bascule), `last`, `save here` (instantané de formation, Shift+clic gauche), `show <n>` (Ctrl+clic gauche), `save selected <n>` quand un sélecteur est actif ;
  * `here` (bridge uniquement) : regroupement sur la position exacte du joueur, en formation, sans cast ;
  * macro construite depuis `GetSpellInfo(30758)` au lieu du nom serveur `aedm` en dur, et boutons grisés tant que le sort n'est pas appris ;
  * nombre de bots sélectionnés affiché dans l'infobulle du bouton racine (l'état des boutons d'unité reste réservé au statut en ligne / hors ligne).
* Achat vendeur bridge-first depuis les composants manquants de recette métier.
* Profession recipes bridge-first.
* Craft de recettes métier via bridge `RUN~CRAFT_RECIPE`.
* Messages d'erreur détaillés pour le craft :
  * feu de cuisine requis ;
  * bot en mouvement ;
  * outil / focus requis ;
  * recette pas prête ou cast refusé.
* RTI bridge-first.
* Pull Control bridge-first.
* Combat Strategies bridge-first.
* Disperse bridge-first.
* Loot Rules bridge-first.
* Quêtes : le serveur envoie maintenant le vrai titre de la quête (et plus l'ID) dans `QUESTS_ITEM`, donc la liste affiche le nom dès la première ouverture.
* Outfits bridge : équipement de deux armes à deux mains (Titan's Grip) — la seconde arme part désormais en main gauche au lieu d'être ignorée.
* Audit v2 (juillet 2026) — corrections :
  * `GetItemInfo(id numérique)` (classe de hard-crash client) supprimé des dernières frames qui l'utilisaient : banque/BDG, toast d'action d'objet, Infos personnage (emblèmes + matériaux de recettes), glyphes du TalentFrame. Nom d'objet résolu via le nouveau helper crash-safe `MultiBot.GetSafeItemName` (tooltip caché, même patron que `GetLocalizedQuestName`), icône via `GetItemIcon`, nom/lien banque parsés depuis la ligne bridge.
  * Watchdog × file d'envoi : `startedAt` d'une requête est maintenant re-tamponné au moment de l'envoi réel (`rawSend`), plus à la création — une requête en attente dans la file ne peut plus expirer avant d'avoir été transmise.
  * `MultiBot.OnBridgeRequestTimeout` implémenté (il était appelé mais jamais défini) : message chat throttlé par type de requête + statut « Request timed out » dans la frame banque/BDG si elle est ouverte.
  * `QUEST_LOG_UPDATE` : handler sécurisé (chaîne de frames défensive) et coalescé (1 refresh par rafale d'événements).
  * Re-dispatch du roster au login corrigé : l'ancienne version posait les globals `event`/`arg1` dépréciés et appelait le script OnEvent sans arguments (no-op silencieux) ; passe maintenant par `MultiBot.DispatchEvent`.
  * `SellAllBots` / `MaintenanceAllBots` : ne whisper plus que les bots confirmés en ligne (`MultiBot.IsBot` + `state`) — plus de whisper aux humains de la guilde / liste d'amis ni aux bots hors ligne.
  * Côté serveur (mod-multibot-bridge) : token bucket par joueur sur les requêtes bridge (`MultiBotBridge.RequestsPerSecond` / `.RequestBurst`, drop silencieux au-delà) + garde nil sur `GetValue<Item*>("item for spell")` dans le ciblage de craft. Nécessite un rebuild serveur.

### Inventory / Inspect / Outfits

* Gestion des outfits.
* Création / remplacement / suppression / équipement d'outfits via bridge.
* Déséquiper le stuff avec clic droit dans la fenêtre Inspect.
* Refresh de l'inventaire en live après action.
* Nouvelle interface inventaire.
* Correction des refresh trop précoces après `u`, `e`, `ue`, `destroy`, `loot`, etc.
* Suppression du spam automatique `items` quand la bridge est connectée.
* Fallback legacy inventory gardé uniquement en diagnostic.

### Spellbook / Talents / Glyphes

* Nouvelle interface Spellbook.
* Spellbook alimenté par bridge.
* Correction « clic droit + glisser vers la barre d'action » : les icônes de sort
  (`createSpellSlotButton`) n'appelaient pas `RegisterForClicks` (un Button ne déclenche
  `OnClick` que sur LeftButtonUp par défaut), donc le clic droit (pickup macro) ne se
  déclenchait jamais. Ajout de `RegisterForClicks("LeftButtonUp","RightButtonUp")` +
  `RegisterForDrag("RightButton")`/`OnDragStart` pour que le glisser fonctionne littéralement.
* Affichage du nom du sort à côté de l'icône : le FontString titre (`T<index>`) existait mais
  était commenté dans `setSpell`. Réactivé (nom au-dessus du rang, police small, tronqué à
  `NAME_MAX_LEN`=15 + « ... », nom complet au survol). Fenêtre élargie (360→480) et colonnes
  réécartées (icône 2/138/274, texte 46/182/318) pour laisser la place au nom.
* Interface talents améliorée.
* Liste des specs alimentée par bridge.
* Interface glyphes alimentée par bridge.
* Affichage des icônes réelles des glyphes.
* Tooltips glyphes via item link, avec fallback spell.
* Correction de l'ordre visuel / ordre playerbots pour les glyphes.
* Suppression du debug local glyph equip après validation.

### Units / Raidus / Stats

* Unit bar dynamique avec auto-collapse.
* Peuplement des EveryBars via bridge.
* Roster/states/details sans spam `.playerbot bot list`.
* Nouvelle interface Raidus.
* Auto-Stats bridge-first.
* Correction online/offline (vue Players) : `IsBridgeRosterBotActive` exige désormais
  `UnitIsConnected` en plus de la présence dans le groupe (un slot raid/groupe garde le nom
  après déconnexion, donc les bots hors-ligne s'affichaient « en ligne »).
* Auto-invite robuste : la file mesure la progression sur l'appartenance réelle au groupe
  (et non sur l'envoi de la commande) et re-parcourt le roster sur quelques tours
  (`MAX_INVITE_ROUNDS`), pour qu'un bot dont l'`add` échoue côté serveur (ex. trop loin /
  autre zone) soit ré-essayé au lieu de laisser un trou.
* Invite de masse = remplir le raid uniquement : `.playerbot bot add` met le bot en ligne même
  s'il ne peut pas être groupé (raid plein), donc la file note chaque bot tenté
  (`invite.attempted`) et, à la fin, déconnecte (`.playerbot bot remove`) tout bot tenté qui
  n'est pas dans le groupe — envois étalés via `TimerAfter` pour ne pas saturer le chat. Plus
  de bot « orphelin » en ligne hors du raid.
* Conversion groupe→raid pendant l'invite de masse : la file appelle `ConvertToRaid()` quand le
  groupe est un groupe plein (vous + 4) avant d'ajouter le 5e bot. Sinon le 6e membre échoue
  silencieusement (« groupe plein ») et le bot de la transition restait en ligne hors raid
  (symptôme « Allin », simplement 5e dans le roster). `isMember`/`toUnit` : seuil raid corrigé
  `> 5` → `> 0` pour reconnaître un raid de 5 fraîchement converti.
* Boutons EveryBar Spellbook/Talent : clic sans effet en raid 40 corrigé. Les boucles
  « désactiver chez les autres bots » parcouraient `index.actives` en indexant
  `units.frames[value]` sans garde ; les bots hors-page n'ont pas encore de frame EveryBar →
  erreur Lua avant l'ouverture du panneau. Extrait dans `disableEveryButtonOnActives` avec
  gardes (comme `disableOtherInventoryButtons`).
* Corrections UI Autostats :
  * adaptation de la frame au texte ;
  * correction du texte sacs tronqué ;
  * correction du rond ovale ;
  * correction du fond bleu ;
  * décalage du nom du bot et de la ligne gold/sacs vers la droite.

### Main bar / options / profils

* Nouvelles fonctions de configuration de l'interface.
* Auto-masquage de la main bar avec réglage du temps.
* Gestion de profils UI.
* Bouton pour cacher Quick Shaman et Quick Hunter.
* Options de déplacement de boutons commencées.
* Passe de simplification (août 2026) :
  * Barre de gauche à **emplacements fixes** (`MultiBot.GetLeftBarSlotX`, défini dans
    `Core/MultiBot.lua`) : plus de reflow dynamique. `refreshLeftLayout` (~190 lignes dans
    `MultiBotMainUI`) supprimé — il était un second propriétaire des positions et écrasait
    silencieusement les échanges de boutons persistés par `BindShiftRightSwapButtons`.
    Invalidation unique de `ButtonLayout:LeftRoot` au premier chargement (`leftBarSlotVersion`).
  * `Disperse` et `Loot` toujours visibles ; l'interrupteur « Switch Disperse » est supprimé.
  * `Stay`/`Follow` : 4 boutons (dont le doublon `ExpandStay`/`ExpandFollow`) réduits à 2,
    toujours visibles et mutuellement exclusifs. L'interrupteur « Expand » est supprimé.
  * Visibilité de `Creator` / `Beast` déplacée dans Options → Layout (mêmes clés sauvegardées,
    le choix existant est conservé) ; ces deux boutons sont placés à l'extrémité de la barre pour
    que les afficher/masquer ne déplace plus rien.
  * Menu principal : 16 → 11 entrées, regroupées panneaux → comportement → actions → GM.
  * Boutons racines : l'état allumé signifie désormais « fonction active » et non « menu ouvert »
    (Disperse affiche la distance en cours, Loot s'allume quand le loot bot est activé).
  * Nouvelles sous-commandes `/mb help`, `/mb help rtsc`, `/mb show`, `/mb hide`, `/mb options`.
  * Units : la pagination a un bouton page précédente (clic droit) et un compteur `page/total`.
  * Correction : `ActionToGroup` / `ActionToTargetOrGroup` testaient `GetNumRaidMembers() > 5`.
    Comme `GetNumPartyMembers()` renvoie 0 en raid, **toutes** les commandes de groupe (stay,
    follow, attack, flee, formation, mode, tanker) échouaient silencieusement dans un raid de 5 ou
    moins. Corrigé en `> 0`, comme `isMember`/`toUnit` l'avaient déjà été.
  * RTSC « Regroup on me » / « Last » : les bots partaient à l'opposé du joueur. Cause côté
    **mod-playerbots** (pas l'addon) : `SeeSpellLocationValue` hérite de
    `MemoryCalculatedValue::Set()`, qui **ignore son argument**, donc `see spell location`
    n'était jamais écrit — ni par `SeeSpellAction`, ni par `ApplyNativeRTSCHere` du bridge.
    La valeur restait `MAPID_INVALID / 0,0,0`, que `operator bool()` considère comme valide,
    et `SetFormationOffset` envoyait donc les bots à la position du joueur **miroir de
    l'origine du monde**. Corrigé par un override `Set` ciblé dans
    `MODULES/mod-playerbots/src/Ai/Base/Value/RTSCValues.{h,cpp}` (additif, limité à RTSC) —
    **nécessite une recompilation du worldserver**. Voir `docs/rtsc.md`.
  * RTSC : emplacements 1..9 qui restaient allumés et `unsave` sans effet — même piège
    `WorldPosition::operator bool()` que le bug « Regroup on me » : une position par défaut
    porte `MAPID_INVALID` et passe donc pour valide. Le test de case vide de
    `SendRtscPackets` (mod-multibot-bridge) vérifie désormais une position réellement
    utilisable. **Recompilation serveur nécessaire.**
  * RTSC : ouvrir/fermer le panneau ne décale plus toute la MultiBar de 34 px (`toggleRTSC`),
    et la restauration au login n'a plus de contre-décalage à rejouer.
  * RTSC : le bouton racine est maintenant le bouton « envoyer » — il lance le marqueur sans
    toucher à la sélection (avant il l'effaçait, donc une sélection construite au clic droit
    ne pouvait jamais être utilisée). Clic droit sur un rôle déjà sélectionné = le retirer.
    Le cast du marqueur affiche enfin un retour en jeu (spot enregistré / bots envoyés / mode
    move / sélection de proximité).
  * RTSC sélection (Tanks / DPS / Healers / groupes) : comportement erratique corrigé.
    Côté serveur `rtsc select` est **additif** (rien ne désélectionne) et un cast au sol
    **remplace** la sélection de tous les bots par « à moins de 10 yards du clic »
    (`SeeSpellAction`). L'addon empilait donc les rôles les uns sur les autres et sur les restes
    du dernier cast. De plus la barre gardait une seconde sélection locale qui divergeait :
    le clic gauche la vidait sans rien envoyer au serveur, `Last`/`go` s'y référaient mais
    **`Move` l'ignorait**. Désormais : clic gauche = « seulement ceux-ci » (`cancel` puis
    `<tag> select`), clic droit = « ajouter », la sélection survit à l'action, `Move` est
    cadré comme `Last`, et le nombre de bots réellement sélectionnés s'affiche en pastille sur
    le bouton RTSC.
  * RTSC : emplacements numérotés, contrôles estompés + message tant que le sort de marquage n'est
    pas appris, retour quand une commande n'atteint aucun bot (`RTSC_ACK` / `POSITION_ACK`
    exposaient déjà `executed`, l'addon le jetait), sélection en attente affichée dans l'infobulle,
    `Browse` n'écrase plus `button.state`, et `GET~RTSC` est réessayé à l'ouverture du panneau.

### Iconos / Itemus / templates

* Nouvelle interface Iconos.
* Nouvelle interface Itemus.
* Données Iconos déplacées dans `Data/MultiBotIconos.lua`.
* Données Itemus déplacées dans `Data/MultiBotItemus.lua`.

### RTI

* Nouvelle interface et fonctions pour la gestion des RTI.
* Bouton `All`.
* Boutons de groupes RTI.
* Dropdowns RTI verticaux vers le haut.
* RTI par bot dans les EveryBars.
* Mémorisation visuelle des icônes RTI choisies.
* Séparation entre :
  * assigner une icône RTI préférée ;
  * déclencher `attack rti target` ;
  * déclencher `pull rti target`.
* Support bridge `RUN~RTI`.
* Allowlist bridge pour les commandes RTI.

### Pull / Combat / Position

* Focus.
* New Pull / Pull Control.
* Mini-frame Pull Control.
* Slider `wait for attack time`.
* Presets Pull Control.
* Actions `pull rti target` et `attack rti target` depuis Pull Control.
* Combat Strategies :
  * `avoid aoe` ;
  * `save mana` ;
  * `threat` ;
  * `behind`.
* Disperse :
  * `disperse set <yards>` ;
  * `disperse disable` ;
  * validation 1 à 100 yards ;
  * messages système de confirmation ;
  * correction du double-clic à l'ouverture ;
  * frame fermée et bouton gris par défaut au login.
* Loot Rules :
  * enable / disable loot ;
  * all ;
  * normal ;
  * gray ;
  * quest ;
  * skill.

### Quick bars / classes

* Bouton pour cacher Quick Shaman.
* Bouton pour cacher Quick Hunter.
* Quick Shaman / Quick Hunter branchées dans l'UI existante.
* Début de nettoyage des tooltips hardcodés vers AceLocale.

### Localisation / qualité

* Tooltips hardcodés de plusieurs fichiers déplacés vers les locales Ace3.
* Ajout / correction de clés de traduction pour RTI et LeftCore.
* Corrections Lua lint déjà traitées :
  * `table.getn` remplacé ;
  * variables inutilisées supprimées ;
  * champs globaux non définis corrigés selon les lots concernés.

## Règles de suivi

* Ne pas supprimer les commandes manuelles utiles :
  * `who`
  * `co ?`
  * `nc ?`
  * `ss ?`
* Ne pas réintroduire de parsing automatique de chat pour ouvrir ou peupler les fenêtres UI.
* Garder les chemins legacy uniquement comme fallback diagnostic quand la bridge est absente ou explicitement autorisée.
* Pour le README, ne pas casser le HTML existant : ajouter uniquement les lignes nécessaires.
* Pour les diffs, toujours se baser sur le zip/code actuel fourni dans le chat.
