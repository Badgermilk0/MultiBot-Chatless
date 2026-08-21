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

### One click convention everywhere: right opens, left executes

Buttons disagreed with each other. Flee and Attack ran their command on **left** and opened their
list on **right**; Formation, Disperse, Loot and the Raid Marker Control did the opposite; the
dozens of pure dropdown roots (RTSC, Creator, Beast, GroupActions, Quests, Units filter/roster,
the per-bot EveryBar panels, every per-class strategy list) opened on **left** with nothing on
right. The rule is now uniform:

* **Right-click opens** — any panel, dropdown, sub-bar or window.
* **Left-click executes** — the button's command. A button with nothing to run does nothing on
  left-click; that is deliberate, so the two sides never trade places from button to button.

56 openers moved to right-click and 6 buttons had their two sides swapped, across `Core/
MultiBotEvery.lua`, all ten `Strategies/*`, and the Formation / Disperse / Loot / RTI / RTSC /
Beast / Creator / GroupActions / Quests / GM / Units (filter, roster, invite, PvP stats, all-bots)
/ MultiBot-menu / bot-bank UIs. Flee and Attack already followed it and are untouched.

Not changed, on purpose:

* **The per-bot roster button** (a bot's name in Units). Right-click there is
  `.playerbot bot remove`; applying the rule would move a destructive action onto left-click,
  where a mis-click kicks a bot out of the group. Left still opens that bot's EveryBar.
* **The Units root button**, whose `doLeft(button, roster, filter)` is a refresh API called from
  seven places, and the **RTSC Browse** / roster **Browse** buttons, which page a row rather than
  open a panel.

Things this had to fix along the way — each one silently breaks otherwise:

* **Leaf buttons re-bind the root.** Picking a default blessing/aspect/totem/aura/presence made
  the leaf write `getButton("Seal").doRight`, which is now the root's *opener*. All 38 of those
  re-bindings write `doLeft` instead, so choosing a default no longer destroys the button that
  opens the list.
* **Two buttons already owned a `doRight`** (`Masters` → `/MultiBot`, Units `Filter` → reset to
  "none"). Those are swaps, not moves; the rename alone would have left the second assignment
  winning and the opener dead.
* **Login restore replays clicks.** `restoreEnableOnlyLeftToggle` (Masters, RTSC) replayed
  `doLeft` to reopen a panel that was left open; renamed to `restoreEnableOnlyOpenToggle` and it
  replays `doRight`. The quest-log refresh in `MultiBotHandler` calls `doLeft` now.
* **The MultiBot bar drags with right-click**, and clicks fire on button *down* — so every drag
  toggled the menu on the way. `OnDragStart` undoes the toggle its own press just made.
* **Tooltips document the click sides.** 67 locale entries had their red click-hint lines
  swapped. Body prose and right-**drag** hints were left alone.

### Combat lockdown (buttons that "did nothing" in combat)

* **Root cause.** `newButton` builds its buttons from `ActionButtonTemplate`, and the whole RTSC
  bar passes `SecureActionButtonTemplate` explicitly (that is what makes `addMacro`'s
  `SetAttribute("type1", "macro")` cast the aedm marker). Both are *secure* templates, so those
  buttons are **protected frames**: while `InCombatLockdown()` is true, insecure code may not
  Show/Hide/move/resize/re-attribute them, and the blocked call raises ADDON_ACTION_BLOCKED —
  which aborts the whole script handler. `newButton`'s `PostClick` opens with the pressed-look
  `SetPoint`/`SetSize`, so in combat the block killed the handler *before* it reached
  `doLeft`/`doRight`. The click did nothing, and with `scriptErrors` off on this client it did so
  silently.
* **Fix** (`Core/MultiBotCombat.lua`, new, loaded right after `Core/MultiBot.lua`):
  `MultiBot.MakeCombatSafe(widget)` swaps the ~20 protected widget methods for wrappers that run
  the call when it is legal and otherwise queue it, replaying the queue on `PLAYER_REGEN_ENABLED`.
  Nothing throws any more, so the button's action always runs and the cosmetic half catches up
  when combat drops. Applied in `MultiBot.newButton` (button + its icon/border/amount regions) and
  `MultiBot.catButton` — the only two factories that can produce a protected frame. Deliberately
  **not** applied to `newFrame`/`wowButton`/`movButton`/`boxButton`: those are insecure widgets on
  unprotected parents, and MultiBot windows sit in `UISpecialFrames`, which ESC walks from a
  secure path.
* **Still impossible, by client rule:** showing/hiding a *secure* button mid-fight (queued to
  combat end instead — only the RTSC row is affected), and `MultiBot.SpellToMacro`, whose
  `CreateMacro`/`PickupMacro` are protected *APIs*. The latter now reports `info.combat_locked`
  via `MultiBot.WarnCombatLocked()` instead of dying inside the click handler.
* `ADDON_ACTION_BLOCKED` is logged to the `core` debug channel (`/mbdebug on core`) so anything
  still blocked can be named rather than guessed at.

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
  * `force` / `unforce` (bridge uniquement) : bouton **Force** — tant qu'il est allumé, les bots vont au bout du déplacement au lieu de l'abandonner dès qu'un ennemi arrive à portée ; ils ripostent toujours en chemin, seul leur déplacement est verrouillé sur la destination. Clic droit = arrêter le forçage et rappeler un déplacement en cours ;
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
* Passe anti-encombrement de la barre de gauche (août 2026, `leftBarSlotVersion` = 3) :
  * Le bouton unique « Combat Modes » (et son dropdown de sélection au clic droit) est remplacé
    par deux bascules indépendantes **Passive** et **Grind** : le bouton allumé est le mode
    réellement actif, au lieu d'un bouton dont le sens dépendait d'un sous-menu.
    `Passive` / `Grind` / `Stay` / `Follow` se dés-allument mutuellement, comme les commandes
    serveur s'annulent entre elles.
  * `Loot` (règles de butin) devient un bouton **optionnel** (Options → Layout, masqué par
    défaut) et rejoint `Creator` / `Beast` à l'extrémité de la barre.
  * `RTI` quitte le panneau Units (« PlayerBot Main Menu ») pour la barre de gauche : bande
    verticale (All, groupes 1-8, Attack, Pull) avec le sélecteur d'icônes qui s'ouvre
    latéralement (`addScopeDropdown(..., sideways)`).
  * La bascule `RTSC` quitte le menu « AddOn Configuration » pour la barre de gauche ; la clé
    sauvegardée `RTSC` est inchangée, donc la préférence existante est conservée.
* Passe d'ordonnancement + nommage (août 2026, `leftBarSlotVersion` = 4) :
  * Ordre de la barre, de gauche à droite : Tank Attack, Attack Commands, Follow, Stay,
    Passive Mode, Grind Mode, Disperse, Flee Commands, Formations, RTSC Bar,
    Raid Marker Control, puis PlayerBot Roster / MultiBot Menu sur la MultiBar elle-même et
    Quest Menu / Group Actions / Summon Group à droite. Les boutons contextuels et optionnels
    (`BotRTI`, `Loot`, `Creator`, `Beast`) restent à l'extrémité gauche.
  * La barre RTSC est **alignée à droite** sur la MultiBar (`RTSC_FRAME_X` = -318 : le bord
    droit du bouton `Force`, à x = 420, tombe sur celui de `Summon Group`, à +102). Elle suit
    le décalage de 38 px appliqué quand le bouton GameMaster apparaît (`doRepos("RTSC", ...)`
    dans `toggleMasters`).
  * Passe de nommage sur tous les boutons de la barre et leurs dropdowns (76 tooltips) : un seul
    gabarit — nom en Title Case, une phrase blanche décrivant l'action, puis les lignes rouges
    clic gauche / clic droit avec leur portée grise `(Executed by: ...)`. Les blocs
    `|cffffffff` non fermés sont corrigés. Renommages notables : « Tank Main Menu » →
    **Tank Attack**, « Attack/Flee Main Menu » → **Attack/Flee Commands**, « Formation Main
    Menu » → **Formations**, « PlayerBot Main Menu » → **PlayerBot Roster**, « AddOn
    Configuration Menu » → **MultiBot Menu**, « Open Quests Menu » → **Quest Menu**,
    « Group Actions Selector » → **Group Actions**, « Group Summon » → **Summon Group**,
    RTI → **Raid Marker Control** (l'acronyme reste dans le corps du tooltip).
  * Nettoyage de la même passe : plus aucun titre « ... Main Menu » dans le fichier de locale
    (les menus de classe des EveryBars deviennent « Mage Buffs », « Paladin Blessings »,
    « Combat Auras », « <Classe> DPS Roles », ...), typo « Shamam » corrigée, les 91 codes
    couleur `|cf9999999` normalisés en `|cff999999`, et les clés orphelines `tips.main.creator`
    / `tips.main.beast` supprimées (plus rien ne les lit depuis le passage de Creator/Beast dans
    Options → Layout).
  * Menu principal : 16 → 11 entrées, regroupées panneaux → comportement → actions → GM.
  * Boutons racines : l'état allumé signifie désormais « fonction active » et non « menu ouvert »
    (Disperse affiche la distance en cours, Loot s'allume quand le loot bot est activé).
  * Nouvelles sous-commandes `/mb help`, `/mb help rtsc`, `/mb show`, `/mb hide`, `/mb options`.
  * Units : la pagination a un bouton page précédente (clic droit) et un compteur `page/total`.
  * Correction : `ActionToGroup` / `ActionToTargetOrGroup` testaient `GetNumRaidMembers() > 5`.
    Comme `GetNumPartyMembers()` renvoie 0 en raid, **toutes** les commandes de groupe (stay,
    follow, attack, flee, formation, mode, tanker) échouaient silencieusement dans un raid de 5 ou
    moins. Corrigé en `> 0`, comme `isMember`/`toUnit` l'avaient déjà été.
  * RTSC « Force Move » : les bots abandonnaient tout déplacement dès qu'un ennemi arrivait à
    portée (contournement manuel : `co +passive` avant, `-passive` après). Ce n'est pas un défaut
    de la barre : un déplacement RTSC est **un seul spline** estampillé `MOVEMENT_NORMAL` que rien
    ne réémet, donc la première poursuite de combat (`MOVEMENT_COMBAT`, priorité supérieure) reprend
    la main au tick suivant. Nouveau drapeau serveur `RTSC force enabled` : `MoveToSpell` mémorise
    la destination et se déplace en `MOVEMENT_FORCED`, et `RTSCForceMoveAction` (stratégie `rtsc`,
    pertinence 100) la réémet jusqu'à l'arrivée. Le bot riposte quand même en chemin — seul le
    déplacement est monopolisé. Fin sur arrivée, délai (`AiPlayerbot.RTSCForceMoveTimeout`), mort,
    changement de carte, `cancel`/`reset` ou `unforce`. Détection automatique comme le verrou de
    sélection : sur un worldserver sans les deux moitiés, le bouton Force est grisé.
    `MODULES/mod-playerbots` + `MODULES/mod-multibot-bridge` — **nécessite une recompilation du
    worldserver** (et une reconfiguration CMake, nouveaux fichiers). Voir `docs/rtsc.md`.
  * RTSC « Force Move » (correctif) : le bouton s'allumait sans que rien ne parte, et ouvrir la
    barre **sans aucun bot** affichait deux erreurs (« worldserver trop ancien », « aucun bot n'a
    exécuté 'enable' »). Même cause : `RTSC_ACK` ne disait que `executed`, donc « 0 bot n'a
    appliqué » et « il n'y a aucun bot » étaient indiscernables. L'ouverture de la barre réémet le
    mode (`unforce`), recevait 0, et **désactivait Force pour toute la session** ; ensuite
    `applyForceMode` posait son drapeau *avant* de sortir, d'où un bouton allumé pour un ordre
    jamais envoyé. `RTSC_ACK` porte maintenant un sixième champ `considered` (bots sollicités) :
    0 sur 0 ne conclut plus rien et le sondage réessaie dès que des bots existent ; les drapeaux ne
    sont posés qu'après un envoi réussi ; les envois automatiques de la barre sont marqués
    *silencieux* (`Comm.RunRtscCommand(..., silent)`) et un clic réel sans bot dit simplement
    « RTSC: no bots online. ». Côté playerbots, `AttackAnythingAction` ne vide plus le motion master
    quand une destination forcée est en cours (seul chemin de combat qui ignorait la priorité de
    déplacement). `MODULES/mod-multibot-bridge` + `MODULES/mod-playerbots` — **nécessite une
    recompilation du worldserver**. Voir `docs/rtsc.md`.
  * RTSC « Regroup on me » / « Last » : les bots partaient à l'opposé du joueur. Cause côté
    **mod-playerbots** (pas l'addon) : `SeeSpellLocationValue` hérite de
    `MemoryCalculatedValue::Set()`, qui **ignore son argument**, donc `see spell location`
    n'était jamais écrit — ni par `SeeSpellAction`, ni par `ApplyNativeRTSCHere` du bridge.
    La valeur restait `MAPID_INVALID / 0,0,0`, que `operator bool()` considère comme valide,
    et `SetFormationOffset` envoyait donc les bots à la position du joueur **miroir de
    l'origine du monde**. Corrigé par un override `Set` ciblé dans
    `MODULES/mod-playerbots/src/Ai/Base/Value/RTSCValues.{h,cpp}` (additif, limité à RTSC) —
    **nécessite une recompilation du worldserver**. Voir `docs/rtsc.md`.
  * RTSC : une case fraîchement enregistrée ne s'allumait qu'après coup. La barre envoyait un
    `save selected <n>` **sans tag**, donc le cadrage reposait sur le flag serveur
    `RTSC selected` — celui-là même qu'un cast au sol écrase par « à moins de 10 yards du
    clic ». Après le moindre envoi le flag était vide, le save ne touchait aucun bot et la case
    restait grise. Les saves passent maintenant par le filtre de chat (`@tank save 4`), comme
    `go`/`last`/`move`, et la case s'allume dès que `UNIT_SPELLCAST_SUCCEEDED` confirme le cast
    (l'état serveur reste l'autorité et corrige si le save n'a rien touché).
  * RTSC : un cast simple « marquait » les bots proches du cercle de ciblage et **désélectionnait**
    ceux qu'on venait d'envoyer (ils sont loin du clic par définition) ; au cast suivant tout ce
    monde partait ensemble, la pastille et le bouton « envoyer » ne parlaient plus des mêmes bots.
    C'est la sélection rubber-band d'origine (`SeeSpellAction`, branche « rien d'armé »).
    La réapplication côté addon ne pouvait pas suffire : le cast est mis en file dans
    `masterIncomingPacketHandlers` et `PlayerbotAI::UpdateAIInternal` vide `HandleCommands()`
    **avant** cette file, donc une commande envoyée au moment du cast est appliquée puis aussitôt
    écrasée — pour tout bot n'ayant pas tické pendant l'aller-retour client, d'où un sous-ensemble
    aléatoire réparé. Corrigé par un verrou serveur `RTSC selection locked`
    (`MODULES/mod-playerbots/src/Ai/Base/Value/RTSCValues.h` + garde dans `SeeSpellAction.cpp`,
    additif et désactivé par défaut), posé/retiré par les sous-commandes bridge `lock` / `unlock` —
    **recompilation du worldserver nécessaire**. En repli (serveur non recompilé, détecté via
    `executed` de `RTSC_ACK`) la réapplication subsiste mais décalée après le rubber-band
    (`RTSC_CAST_SETTLE + 0,25 s`) puis **vérifiée** contre les flags par bot renvoyés par
    `GET~RTSC`, avec au plus deux reprises. Sans sélection explicite le rubber-band d'origine est
    conservé. Fermer le panneau vide aussi la sélection affichée (le `cancel` la vidait déjà côté
    serveur).
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
  * RTSC : l'affichage restait un clic en retard sur un état que la barre pilotait pourtant
    correctement — une case enregistrée ou supprimée ne changeait d'aspect qu'à l'action suivante,
    et une sélection faite au simple cast (rubber-band, sans rôle sélectionné) n'apparaissait
    jamais sur la pastille. Trois causes, toutes côté addon :
    * `SeeSpellAction` travaille sur le paquet **sortant** du maître (`CMSG_CAST_SPELL`), donc un
      cast fait tout son effet sur les bots même si le serveur ne renvoie jamais
      `UNIT_SPELLCAST_SUCCEEDED` — or tout le rafraîchissement post-cast en dépendait.
      `UNIT_SPELLCAST_SENT` est ajouté **en secours** (différé de 1 s, annulé si `SUCCEEDED` a
      déjà traité le cast) : l'événement fiable garde la priorité et un cast n'est jamais traité
      deux fois.
    * `save` / `save here` / `unsave` passent par la file de commandes des bots : la relecture qui
      suit l'action peut répondre **avant** qu'ils l'aient appliquée. Les marques optimistes sont
      donc horodatées (`markSlotPending`) et tiennent `RTSC_CAST_SETTLE + 1 s`. Supprimer une case
      ne relit plus l'état immédiatement (course perdue d'avance) : repeinte tout de suite, relue
      après le délai de stabilisation, comme l'enregistrement.
    * Relecture de fond toutes les 5 s tant que la ligne RTSC est ouverte : tout ce que le maître
      n'a pas demandé explicitement (sélection rubber-band, commande arrivée après sa relecture,
      bot reconnecté) n'avait aucun chemin vers l'écran. Suspendue pendant qu'une relecture
      délibérée est en attente, arrêtée dès que la ligne est masquée.
  * RTSC : 8 boutons de groupe au lieu de 5 — un raid compte huit sous-groupes et le filtre
    `@group<n>` de playerbots lit `GetSubGroup() + 1` sans borne haute (`SubGroupChatFilter`),
    donc les groupes 6 à 8 étaient adressables depuis toujours, la barre ne les dessinait pas.
    Aucun changement serveur. `Icons/` ne fournit d'art que pour 1-5 : 6-8 reprennent l'icône RTSC
    générique avec leur numéro sur la face (comme les emplacements). La rangée de groupes allant
    désormais jusqu'à x=240, le bloc toujours visible glisse d'un cran à droite (`@all` 270,
    Browse 300, séparateur 301, Move 330, Last 360, Here 390). Infobulles ajoutées dans les
    8 fichiers de locale (réduits depuis au seul `enUS`, cf. « Localisation / qualité »).

* Options qui « ne se sauvegardaient pas » (août 2026) — `Lock main bar movement` et
  `Enable loot window` :
  * Les valeurs étaient bien persistées ; c'est la **lecture** qui était fausse.
    `MultiBot.GetX and MultiBot.GetX() or true` renvoie `true` quand le getter renvoie `false`
    (idiome `and/or` de Lua), donc les deux cases repartaient cochées à chaque construction du
    panneau — et l'onglet Layout AceGUI est reconstruit à **chaque** changement d'onglet, pas
    seulement à la connexion. Remplacé par `readBoolSetting` / `readNumberSetting`
    (`UI/MultiBotOptions.lua`), qui ne retombent sur le défaut que pour `nil` / mauvais type.
  * `Lock main bar movement` avait en plus un vrai défaut de comportement : `applyMoveLockState()`
    est appelé depuis `InitializeMainUI`, donc au chargement des fichiers, **avant** que
    `Config_Ensure` n'ait branché le profil AceDB — la valeur enregistrée était illisible et le
    verrou se figeait sur le défaut (verrouillé) pour toute la session. `OnDragStart` relit
    maintenant la config (`UI/MultiBotMainUI.lua`), comme le fait déjà l'`OnUpdate` de
    l'auto-masquage juste en dessous.

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
* Contrôle RTI déplacé du panneau Units vers la barre de gauche (bande verticale, sélecteur
  d'icônes latéral).

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

* **English-only branch.** Removed the seven non-English locale files (`frFR`, `esES`,
  `deDE`, `enGB`, `ruRU`, `zhCN`, `koKR`) and the empty `Locales/MultiBotAceLocale.lua`
  stub; `Locales/MultiBotAceLocale-enUS.lua` is now the single locale file and registers
  itself as the AceLocale default, so any client locale resolves to it. Also dropped, as
  dead code on an English client: the per-locale pet names in `Data/HunterPetList_*`
  and `PET_FAMILY_L10N`, the localized class aliases and multi-language account-level
  patterns in `Core/MultiBot.lua`, the zhCN branch in `UI/MultiBotStats.lua`, and the
  Chinese/German chat-parsing branches in `Core/MultiBotHandler.lua`,
  `UI/MultiBotInventoryFrame.lua`, `UI/MultiBotSpell.lua`, `UI/MultiBotItemusFrame.lua`
  and `UI/MultiBotPVPUI.lua`. All French comments and French user-facing strings
  (slash-command output, layout error codes, `CreatorUI` gender labels, the `InspectUI`
  unequip hint, `Options` fallbacks) are now English.
  Follow-up (not done): this `TODO.md` and `docs/m12-debug-mode-emploi.md` are still
  written in French.
* Tooltips hardcodés de plusieurs fichiers déplacés vers les locales Ace3.
* Ajout / correction de clés de traduction pour RTI et LeftCore.
* Corrections Lua lint déjà traitées :
  * `table.getn` remplacé ;
  * variables inutilisées supprimées ;
  * champs globaux non définis corrigés selon les lots concernés.

### Quality pass (scheduler, namespace, dead code)

* **Timer scheduler rewritten (`Core/MultiBotAsync.lua`).** `TimerAfter` used to
  `CreateFrame("Frame")` per call whenever `C_Timer` was missing — which is always on
  3.3.5a — and WoW never garbage-collects frames. The request watchdog re-arms itself
  every 2.5s for the whole session, so the addon leaked a permanent frame roughly every
  2.5 seconds. There is now one shared OnUpdate driver with a pending list; it hides
  itself when nothing is scheduled. Timers created from inside a firing callback are
  spliced in after the pass, so `NextTick` still means "next frame" and a
  self-rescheduling callback cannot spin within one frame. Added `MultiBot.CancelTimer`
  (handle returned by `TimerAfter`/`NextTick`). `_G.TimerAfter` is still published for
  compatibility, but a pre-existing global of that name is no longer adopted.
* **Chat throttle no longer runs an OnUpdate while idle** (`Core/MultiBotThrottle.lua`):
  the flush frame is shown on enqueue and hides itself when the queue drains; tokens
  refill from elapsed wall-clock on wake-up, so an idle period still restores the burst.
* **Locale strings stopped polluting the addon namespace.** `ApplyLocaleKeyValues`
  exploded every dotted key into nested tables on the `MultiBot` global (~1000 keys);
  nothing ever read them, and the first path segment silently pre-created
  `MultiBot.inventory` / `.talent` / `.spellbook` / `.spec` before the real UI frames
  claimed those fields. The function and its call are gone; `MultiBot.L` is the only
  lookup path, and it now caches the resolved AceLocale table instead of re-resolving it
  on every tooltip.
* **Fixed nil-call bugs found by tightening the lint allowlist:**
  * `UI/MultiBotInventoryItem.lua` — the destroy-confirmation popup closed over
    `sendInventoryItemCommand` before its `local` existed, so it compiled against the nil
    global and OnAccept threw instead of destroying the item (forward-declared).
  * `UI/MultiBotTalentFrame.lua` — `getGlyphItemType` called `ensureHiddenTooltip`, a
    file-local of `MultiBotAceUI.lua`; now uses `MultiBot.AceUI.EnsureHiddenTooltip`.
  * `Core/MultiBotEngine.lua` — `substr(...)` is not a WoW global (now `strsub`); `tParts`
    and `tSpace` were accidental globals (now locals).
  * `UI/MultiBotInventoryFrame.lua` — window title fell back to `MB_INVENTORY_LABEL`,
    which was never defined anywhere; now a localized `inventory.title`.
  * `UI/MultiBotTalentFrame.lua` — `strsplit(",%s*", …)` passed a Lua pattern to an API
    that takes delimiter *characters*.
* **Quests All (Group) works in a raid** (`UI/MultiBotQuestsMenu.lua`): it enumerated only
  `GetNumPartyMembers()`, which is 0 in a raid, so the awaiting-bot set was empty while
  `ActionToGroup` broadcast to RAID and the aggregation never completed.
* **Reset window positions is nil-safe** (`UI/MultiBotMainUI.lua`): windows are built
  lazily, so it no longer throws on the first one that has not been opened yet and leaves
  the remaining windows unmoved.
* **Namespace hygiene:** `ShowPrompt` and `HandleQuestsAllResponse` are no longer globals
  (`MultiBot.ShowPrompt` / file-local); generic names like these can collide with any
  other loaded addon.
* **Dead code:** deleted `UI/MultiBotIconos.lua` (6,004 lines) — it was not in
  `MultiBot.toc` at all, and is a stale copy of `Data/MultiBotIconos.lua` plus an
  `addIcons` superseded by `UI/MultiBotIconosFrame.lua`.
* **Lint config** (`.luacheckrc`): `std` is now `lua51` (was `lua53`, which accepted syntax
  and library calls the client does not have), and the allowlist entries that were masking
  the accidental globals/typos above were removed.
* Localized the last hardcoded UI strings and the remaining French user-facing text
  (`tips.every.characterinfo` "Infos personnage", the throttle banner's "rafale", the
  quest-log tooltip's "Groupe :"), and added the two `tips.every.*` keys that were missing
  from the locale table entirely.

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
