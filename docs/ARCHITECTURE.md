# opx77_appearance — architecture

`opx77_appearance` est le service d'apparence d'Opx77 côté client : il dépense le bootstrap de
personnage à la connexion, remet le personnage sur son corps, restaure son visage, envoie
`open77:session:gameplayReady`, ouvre le miroir de Cyberpunk pour l'éditer ou le créer, remet
les vêtements stockés et les enregistre, et fait passer le look de chaque joueur aux autres. Il
ne stocke rien : le visage et les vêtements appartiennent à `opx77_core`, qui valide et écrit ;
la moitié serveur ne tient les looks qu'en mémoire. Il ne décide jamais qu'un joueur doit passer
par un créateur : `opx77_charcreator` et `opx77_charselector` en décident et appellent ses
exports. Le code est commenté en anglais, cette documentation est en français ; le mode d'emploi
(exports, événements, configuration, locales) est dans le `README.md`.

## Manifeste

Les scripts partagés chargent d'abord : `config.lua`, `shared/locale.lua`, puis les catalogues
`locales/en.lua` et `locales/fr.lua` juste après le module, pour qu'aucun fichier plus bas
n'appelle `locale()` contre un catalogue vide.

Côté client, l'ordre porte : `client/snapshot.lua` crée `OpxAppearance.Snapshot` avant
`client/state.lua`, dont la garde contre une restauration redondante compare deux visages ;
`client/main.lua` crée `OpxAppearance.Runtime`, que `client/editor.lua` lit au chargement ;
`client/panel.lua` vient après l'éditeur, car une ligne du panneau ouvre le miroir ;
`client/clothing.lua` vient après `main.lua`, dont il lit l'état réglé, et publie sur
`OpxAppearance.Clothing` ce que `client/presence.lua` lit au chargement juste après : les listes
d'emplacements (`SLOTS`, `OUTFIT_SLOTS`), l'enregistrement par défaut (`DEFAULT`, jamais écrit),
l'égalité par contenu (`Same`) et le test de famille d'un objet (`Fits`) ; `client/exports.lua` est
le dernier, puisque publier la surface lit tout le reste.
`State.EnterWorld` et `SwitchBody` lisent `OpxAppearance.Clothing` et `OpxAppearance.Presence`
au moment de l'appel, avec une garde, parce que ces modules chargent après eux.

`server/presence.lua` est la seule moitié serveur : elle fait passer le look de chaque joueur aux
autres, comme `open77_appearance` et ses relais `open77_equipment` / `open77_wardrobe`, et ne
stocke rien.

`reload_policy "local"` : un rechargement est un rechargement de scripts, pas une reconnexion. Le
visage est relu dans `PlayerData` (`catchUp`), le panneau est retiré, et rien d'autre ne
survit.

- `network.events` — les deux moitiés : `TriggerServerEvent` pour le visage, les vêtements et le
  look, et les looks que le serveur renvoie à chaque client. `local.events` n'est pas nécessaire.
- `player.appearance.read` — lire le catalogue et capturer le visage ; `captureBody` en a besoin
  aussi. Sans `edit`, la resource sauverait un visage sans jamais le remettre.
- `player.appearance.edit` — écrire le visage sur le puppet, ouvrir le miroir, recharger le corps.
- `player.equipment.read` — le registre d'équipement et la garde-robe, pour le look publié et pour
  relire les vêtements.
- `player.equipment.edit` — `Open77.equipment.apply` et `Open77.wardrobe.outfit().apply` /
  `activate`, pour remettre les vêtements stockés sur le puppet de ce joueur, et de personne
  d'autre.
- `puppets.present` — `Open77.puppets.setBody`, `setSlot` et `setWardrobe`, pour mettre le look
  d'un autre joueur sur le proxy de ce client.
- `players.life.read` — l'état de vie du joueur local, en lecture : aucun visage ni éditeur ne
  part sur un joueur derrière l'écran « continuer » ou pendant la réapparition qu'un
  rechargement de corps rejoue.

Pas de `webui.*` : la resource ne dessine rien elle-même, le panneau est une liste
d'`opx77_menu`. Délibérément non demandés : `database.access`, les écritures `players.life.*`,
`world.*`, `combat.config` — `opx77_core` possède le visage, les vêtements et chaque écriture.
Aucune `dependency` n'est déclarée : `opx77_core`, `opx77_menu` et `opx77_notify` sont sondés par
`GetResourceState` et par la réponse des exports.

## Contrats

- **Douze exports client**, chacun répond une table portant `ok` et ne lève jamais.
  L'appelant vient de `GetInvokingResource()` : un appel sans resource invocante (depuis
  l'intérieur de la VM) est refusé par `export_call_required`, puisque rien d'interne ne devrait
  atteindre la surface publique. La génération (`GetInvokingResourceGeneration`) sert à retirer le
  panneau d'un appelant rechargé. Une levée d'`Open77.appearance.isOpen` compte comme une modale
  à l'écran partout (`Runtime.ModalOnScreen`) : `isOpen` répond `open = true`, `openEditor` et
  `openCreator` répondent `appearance_busy`, au lieu de lever.
- **Une écriture répond qu'elle a été demandée**, jamais qu'elle a eu lieu : `setSkin`,
  `saveSkin`, `openEditor`, `openCreator` et `openPanel` répondent `queued = true`, et le résultat
  arrive sur `OPX_APPEARANCE_CONFIG.EVENT` (`applied`, `saved`, `created`, `panelOpened`...).
  `Editor.Save` publie un `saved` inchangé par `SetTimeout(0, ...)`, après la réponse de l'export,
  sinon un appelant qui commence à écouter sur la réponse le manquerait.
- **`isSettled`** est la question du portail ; `state` est le rapport de diagnostic derrière, et
  n'expose rien qu'un appelant pourrait prendre pour une autorité. Son champ `body` vient de
  `Runtime.BodyFamily` plutôt que de l'état : après un redémarrage, seul le bootstrap le sait
  encore.
- **Événements vers `opx77_core`** : `opx77:server:saveAppearance { snapshot }` et
  `opx77:server:saveClothing { citizenId, clothing }`. Réponses : `opx77:client:appearanceSaved`,
  `opx77:client:clothingSaved`, et `opx77:client:refused (code, _, operation)`. L'opération décide
  à qui est le refus : le core refuse une sélection de personnage ou un spawn de véhicule avec les
  mêmes codes (`error.tooFast`), donc `client/editor.lua` ne prend que `saveAppearance`
  (`OPX.Operations.SAVE_APPEARANCE`) et `client/clothing.lua` que `saveClothing`.
- **Événements réseau de présence** : `opx77_appearance:present`, `:absent`, `:replay` du client
  vers le serveur ; `:presentAck`, `:replayed`, `:look`, `:resend` du serveur vers les clients.

## Le portail de readiness et le bootstrap

`open77:session:gameplayReady` est le seul signal qui lève le hold `__platform` de la
plateforme : sans lui personne n'apparaît. `Runtime.Announce` l'envoie au plus une fois par
entrée dans le monde, et seulement pour un personnage chargé, puisque `State.AppearanceSettled`
est faux tant qu'aucun ne l'est. `AppearanceSettled` attend : un personnage, un visage décidé, pas
de création ni de rechargement de corps en cours, pas de `needsCreation` sans réponse (l'éditeur
peut encore venir), pas de capture de création chez le core, la génération de restauration réglée,
et, pour une restauration mise en file, la confirmation du miroir et le reset du joueur. Une
restauration **échouée** est un état réglé honnête : elle ne doit pas bloquer le joueur derrière le
portail.

Le monde vient d'abord. Le cache de chargement du shell reste levé tant que le bootstrap de
personnage n'est pas dépensé, et toute surface OPX//77 est dessous : `Runtime.BeginBootstrap` le
dépense à la connexion, une fois par connexion, avant qu'un personnage soit choisi. Le monde du
menu d'avant-jeu lève `open77:worldReady` lui aussi, avec le bootstrap encore `waiting`. Le corps
est celui du dernier personnage joué (`lastLoggedOut` le plus haut du roster), lu dans ce que le
core tient déjà (`charactersReady`, `GetCharacters`) toutes les `ROSTER_POLL_MS`, jamais demandé :
le core refroidit les demandes de roster à 2000 ms et jette l'excédent. Le miroir vide du core
répond zéro personnage et zéro slot ; un compte sans personnage a encore un slot, donc zéro
personnage avec des slots est un vrai roster vide. Le core envoie le roster le plus récent en
premier ; `lastPlayedFamily` ne fait que garder cet ordre, et seulement entre deux horodatages de
même type comparable. L'`await` de `heldRoster` est hors `pcall`, seul l'envoi est protégé : un
`yield` ne traverse pas un `pcall`.

`Runtime.ResolveCharacter` le dépense aussi quand un personnage est chargé avant : ce personnage
a le meilleur droit sur le corps ; un personnage dont la famille est illisible laisse le choix au
bootstrap de la connexion plutôt que de le faire échouer. Un second appel pour la même entrée est
normal et ne fait rien.

`markWorldEligibility` n'est appelée que depuis les événements d'entrée dans le monde : un
sondage lirait `ready` trop tôt. Au démarrage de la resource, aucun `worldReady` ne suit une
republication dans un monde vivant, donc l'éligibilité est rétablie dans `onClientResourceStart`,
et le même test de phase empêche un démarrage tombé dans le menu d'annoncer. `catchUp` rattrape un
personnage déjà chargé, puisqu'un rechargement en cours de session manque toutes les émissions et
qu'il n'y a pas de rejeu.

## Où un visage peut aller

`inGameplay` ne suffit pas : `attached` est vrai aussi pour le puppet du menu et pour celui
derrière l'écran « continuer », et le puppet du menu répond attaché, vivant et à 100 de santé.
`Runtime.Faceable` exige donc le monde de jeu, pas de rechargement, le reset pristine
`complete` (lu en direct dans `characterBootstrap().playerReset` : il ne revient à `complete`
qu'à la fin d'un reset, alors que `open77:playerReset:complete` peut être manqué par un
rechargement), et une phase de vie `alive` ou `recovering` — celles depuis lesquelles la cabine
d'essayage de la plateforme passe le joueur au miroir natif. `lifePhase` répond `false` sans
phase (derrière « continuer ») et `nil` quand la lecture est impossible, ce qui ne bloque rien ;
elle le dit une fois dans le journal.

Après un rechargement de corps, `Faceable` attend aussi la fin de la réapparition que la
plateforme rejoue, jusqu'à `BODY_RELOAD_SETTLE_MS`. L'éditeur que le jeu n'a jamais consommé
avait été demandé pendant le reset, juste avant cette réapparition ; on ne sait pas lequel des
deux le gênait, donc les deux sont attendus. Le plafond fait qu'une phase qui ne lit jamais
`alive` coûte une attente, pas un joueur.

`awaitWorld` n'a pas de limite de temps — il attend qu'un humain appuie sur une touche — mais
dit une ligne après une minute.

## Le corps appartient au personnage

La famille de corps est `charInfo.gender` sur la ligne du personnage, et `opx77_core` la
possède. `openEditor` ne passe jamais de genre au miroir ; `openCreator` passe celui du
personnage, et un éditeur de création revenu sur l'autre corps est refusé et rouvert.

`Runtime.BodyFamily` lit le moteur (`captureBody`), sinon la famille que ce client a chargée,
sinon celle que le bootstrap a résolue : `captureBody` peut ne rien répondre avant le reset du
puppet de jeu, voire jamais sur certains builds, et un redémarrage de la resource oublie ce
qu'elle a chargé ; sans le bootstrap, le corps paraîtrait inconnu et serait rechargé pour rien.

Seul un rechargement montre l'autre corps. `ensureFamily` remet le puppet sur la famille du
personnage avant tout visage, puisque le bootstrap a chargé le corps du dernier joué et que le
personnage sélectionné n'est pas forcément celui-là. `reloadOntoFamily` compte contre
`FAMILY_RETRIES` et ne dit `bodyLoadFailed` que si le moteur ou ce client sait que le corps est
l'autre. `SwitchBody` déshabille l'état (le puppet sera pristine) et retire le corps aux
observateurs (`Presence.Withdraw`) jusqu'à la publication suivante.

### Un rechargement, pas à pas

`switchBodyFamily` attache le monde **deux fois** : un retour couvert au menu, puis la sauvegarde
cible, et les deux lisent `ready`. Aucune de ces entrées ne termine donc le rechargement.
`Runtime.FinishReload` le termine au reset pristine du nouveau puppet —
`open77:playerReset:complete`, la seule entrée d'un rechargement où un visage peut aller, puisque
le puppet du retour au menu n'a jamais de reset — ou, si cet événement ne parvient jamais à la
resource, `Runtime.WatchReload` suit la projection de reset de l'hôte : juste après la bascule elle
lit encore le `complete` de l'ancien puppet, donc seul un **retour** à `complete` après l'avoir
quitté compte (`State.reloadResetSeen`). Un rechargement qui échoue avant d'atteindre un monde est
terminé par `takeBodyFamilyTransition` (`error:<raison>`) : aucun rechargement ne vient, le monde
est rejugé et le visage décidé sur le corps qu'il a.

La transition `edit:<famille>` arrive avec le monde cible, avant le reset de son puppet :
`openCreator` attend le reset et la réapparition. Seule une création demande une transition
d'édition ; la restauration revient par l'entrée dans le monde. Une création dont le
rechargement est entré dans le monde sans que la transition réponde est rouverte par le worker,
sinon le portail l'attendrait pour toujours.

## Mettre un visage

`Open77.appearance.apply` ne fait que **mettre en file** le miroir caché : la confirmation
(`open77:appearance:confirmed`) et le reset du joueur arrivent plus tard, en événements séparés, et
l'annonce les attend. La même confirmation sert aux deux modales et à la restauration : ce qui est
ouvert décide, pas l'événement.

- **Garde contre la restauration redondante.** Réappliquer un visage que le puppet porte déjà arme
  un watchdog natif sans rien à ouvrir, qui finit en erreur visible sur un visage correct.
  `State.Wearing` le détecte ; un rechargement de corps déshabille l'état, donc un visage porté ici
  l'est sur le bon corps. `State.Wore` n'est appelé qu'une fois un apply accepté, jamais quand il
  est seulement en file.
- **Tentatives.** `RETRYABLE` sépare « pas encore » de « non » ; tout autre refus est final. La
  restauration de connexion a vingt tentatives contre huit pour un apply en cours de session : elle
  couvre aussi la courte fenêtre de readiness monde/menu. `body_gender_switch_requires_reload` veut
  dire que le moteur ne distinguait pas le corps avant l'apply : `bodyReloading` retient l'annonce
  jusqu'au tour suivant.
- **`open77:appearance:restore_failed`.** Si l'abandon concerne la restauration que l'annonce
  attend, l'enregistrement optimiste est retiré et la restauration relancée, jusqu'à
  `RESTORE_RETRIES` ; cet événement ne part qu'une fois le pont sondé, donc il ne peut pas boucler.
  Sinon, la garde `State.Wearing` retourne **avant** de vider les drapeaux, qui bloqueraient un
  joueur dont le visage est juste.
- **`Runtime.FinishMutation`** libère la transaction de mutation native. Ouvrir le miroir de
  restauration pendant qu'un commit est en cours répond toujours `appearance_editor_busy`, d'où
  le `rollback` qui la libère **d'abord**. Après un enregistrement, `ReFinalizeState` met du
  travail en file dans le système de personnalisation : un budget d'une frame (`SetTimeout(250)`)
  précède la libération.
- **`Runtime.BeginPristine`** prend lui aussi une génération de restauration, pour que l'annonce
  attende le corps comme elle attendrait un visage.

## Les modales

`client/editor.lua` tient les deux transactions. `State.creating` couvre la création entière,
d'`openCreator` à la réponse du core, et reste vrai tant que le core n'a pas répondu, puisque
l'annonce l'attend ; `State.creatorUp` ne couvre que l'éditeur à l'écran. Il n'y a pas de délai
tant que la modale est ouverte : un joueur qui hésite une heure n'est pas une faute. Une seule
ouverture à la fois (`creatorOpening`) : après un rechargement, la transition et le worker peuvent
demander tous les deux. `open` répond vrai à une demande mise en file que le jeu peut ne jamais
consommer, et aucun appel ne retire un éditeur en file : `watch` le dit une fois après
`CREATOR_UNSEEN_MS`, et une levée de `isOpen` compte comme « à l'écran », comme pour le panneau.

`Editor.Open` teste `creating` avant le test d'occupation : le créateur compte comme une modale à
l'écran, et le refus général cacherait le spécifique (`character_creation_in_progress`). Il refuse
aussi pendant qu'une capture est chez le core : sa réponse remettrait le puppet et libérerait la
transaction sous un miroir ouvert. L'avertissement `editorDefaultFace` est dit **avant** que le
miroir apparaisse : un éditeur qui s'ouvre en silence sur le visage par défaut se lit comme un
personnage effacé.

`send` attend le cooldown du core (`SAVE_COOLDOWN_MS`) au lieu de le déclencher : un refus pour
aller trop vite coûterait la capture. Le délai du commit reste à 0 tant que l'événement n'est pas
parti, pour que le worker ne l'expire pas pendant l'attente. Le core n'écrit ni ne publie rien pour
un visage identique au stocké : une confirmation inchangée est donc terminée ici, sinon elle
expirerait sur un enregistrement correct. `opx77:client:appearanceSaved` est la seule confirmation
qui existe ; un visage stocké par autre chose que ce client est remis sur le puppet.

`enterPristine` termine une création qui n'a rien stocké et laisse entrer le joueur sur le visage
pristine de son propre corps. Le personnage existe, seul son visage manque, et le monde est déjà
chargé : rien n'échoue. La création n'est plus rouverte pour ce personnage (`creation_refused`),
sinon elle reviendrait sur quelqu'un debout dans Night City ; `openEditor` est le chemin du retour
et enregistre le premier visage comme n'importe quelle capture. `Runtime.WarnUnanswered` dit une
fois qu'aucun créateur n'a répondu à `needsCreation` en `CREATION_WAIT_MS`, plutôt que de tenir le
portail pour un créateur qui ne vient pas.

Tout ce qui doit être regardé plutôt qu'attendu passe par deux threads, un par cadence : une
resource client a droit à 1024 tâches, et un thread par transaction est la façon de les épuiser.
Toutes les `WATCH_MS` (200 ms), celui de `client/editor.lua` fait `watch` (création sans réponse,
transition de corps, éditeur de création invisible, délai de capture), puis
`Runtime.WatchReload`, puis `Runtime.Announce`. Chaque seconde, celui de `client/presence.lua` fait
`Clothing.Check` puis `Presence.Check`. Chaque fichier plus tardif appelle directement le
précédent ; l'ordre dans une passe est celui des anciens threads séparés.

## Le panneau

Une liste dessinée par `opx77_menu`, pour un appelant à la fois, clé `GetInvokingResource()`.
`opx77_menu` est optionnel : absent, `openPanel` répond `menu_not_running` et rien d'autre ne change.
Le spec est rendu entier ici : `opx77_menu` ne tient ni catalogue ni règle de cette resource. Une
ligne non actionnable porte sa raison comme valeur, parce qu'une ligne grisée sans rien à côté se
lit comme cassée. Rouvrir est un redessin : aucun niveau ne peut être demandé.

Le miroir de Cyberpunk est le seul éditeur de visage qui existe, et une liste laissée par-dessus lui
prend ses flèches : `nativeUp` compte une réponse illisible comme « à l'écran », et `tick` retire le
panneau (`appearance_busy`). `openNative` retire le panneau et attend la réponse d'`opx77_menu` au
`close` **avant** de demander la modale. `session` monte à chaque ouverture et chaque fermeture :
un `open` encore en vol quand le panneau a été retiré trouve sa session partie et referme la liste
au lieu de l'adopter. La fermeture par le menu est reconnue au propriétaire plutôt qu'au handle,
puisque `opx77_menu` peut retirer une liste avant que son export `open` ait répondu. `watch`
protège `tick` par `pcall` et ne journalise qu'une fois par série d'échecs. `wearStored` lit le
visage et le personnage avant le `yield` : un changement de personnage pendant l'apply est un autre
visage.

## Les vêtements

`PlayerData.clothing` porte un enregistrement par personnage — les neuf emplacements, les sept
tenues de garde-robe, l'active — en tant qu'enregistrement, `false` quand rien n'est stocké, ou
`nil` quand le core n'a pas pu en lire un ou ne stocke pas de vêtements. Un enregistrement va sur le
puppet une fois le visage de cette entrée réglé et l'annonce partie, là où le service de
présentation de la plateforme met les siens ; `false` met l'enregistrement que ce service donne à
un personnage sans ligne (tout vide sauf `Items.Underwear_Basic_01_Bottom`, pas de tenue) ; `nil`
ne touche rien et n'enregistre rien.

- **La barrière.** `ready` exige le visage de ce personnage réglé et annoncé, un puppet où un
  visage peut aller, et ni modale, ni commit de visage, ni rechargement ; la garde-robe de la
  plateforme attend la même barrière de mutation du corps. Une levée d'`isOpen` compte comme « à
  l'écran ». Un changement vu avant la fermeture de la barrière doit tenir de nouveau après.
- **Mettre.** `putOn` remplace chaque tenue, choisit l'active, puis déclare les neuf emplacements,
  avec `allowRestricted` comme le relais de la plateforme. La garde-robe d'abord : un emplacement
  vidé sous une tenue affichée garde les visuels de la tenue. L'acceptation n'est pas
  l'achèvement : `verify` relit. `fit` retire un objet que la famille ne peut pas porter, comme le
  montre l'enregistrement de la plateforme, et un objet que le moteur ne connaît plus (une mise à
  jour l'a retiré), sinon l'enregistrement ne se relirait jamais et plus rien ne s'enregistrerait.
  Une recherche de l'objet que tout corps possède distingue « objet inconnu » de « pas de
  catalogue maintenant » ; sans catalogue rien n'est retiré. Seul ce qui est mis est ajusté : le
  stockage garde l'objet jusqu'à ce que le joueur change quelque chose.
- **Relire.** Toutes les `VERIFY_MS`, jusqu'à `RESTORE_ATTEMPTS` fois ; ensuite rien n'est
  enregistré pour le reste de l'entrée, puisque ce que porte le puppet n'est pas le choix du
  joueur et qu'un enregistrement l'écraserait. `normalize` met les deux côtés de toute comparaison
  sous la forme canonique du core ; dans une tenue, `false` masque l'emplacement et une absence
  montre ce qui est porté ; `wardrobe.active` `false` veut dire « pas de tenue », `nil` illisible.
- **Enregistrer.** Une valeur différente de la dernière mise ou envoyée, qui tient
  `CLOTHING.SAVE_DEBOUNCE_MS` (un joueur qui essaie trois vestes enregistre celle qu'il garde),
  part après le cooldown du core. Un look que le core tient déjà — un changement défait, ou refusé
  avant — n'est pas envoyé : le core répondrait par le silence. `error.tooFast` est retenté ;
  `clothing.stale` et `error.notLoggedIn` veulent dire qu'un changement de personnage est passé
  avant ; un look refusé lui-même n'est pas retenté, un changement ultérieur l'est. `STRIKES`
  échecs d'affilée (sans réponse en `COMMIT_MS`, ou `error.unavailable`) arrêtent l'enregistrement
  jusqu'au prochain chargement, et le joueur est prévenu une fois (`tell`).
- **Présence.** `Clothing.Settled` retient le look publié jusqu'à ce que les vêtements soient mis,
  abandonnés, ou attendus `PRESENCE_HOLD_MS` : un joueur dessiné un instant dans de mauvais
  vêtements vaut mieux qu'un joueur pas dessiné du tout.

`CLOTHING.PERSIST = false` et un `open77_appearance` en marche laissent les vêtements tranquilles.

## Les looks des autres joueurs

Un observateur ne dessine un autre joueur qu'à partir de ce qu'on lui donne : le corps
(`Open77.puppets.setBody`), chaque emplacement (`setSlot`) et la garde-robe (`setWardrobe`). Le
moteur n'en réplique aucun, et les relais `open77_equipment` / `open77_wardrobe` ne tournent pas
sans `open77_appearance`. Un proxy sans look n'est jamais habillé : le joueur n'est pas là.

- **Client.** `client/presence.lua` publie le corps, le registre d'équipement et la tenue active
  une fois annoncé sur son visage réglé, dans ses vêtements, sans éditeur ni rechargement ; puis
  chaque fois que cela change, ou quand le serveur n'a pas répondu en `RETRY_MS`. Chaque entrée
  dans le monde et chaque retrait font avancer la séquence, donc une réponse à une demande plus
  ancienne ne règle rien. Il demande le look de tous après chaque entrée dans le monde, quel que
  soit l'état du sien, et seulement depuis le monde de jeu : les puppets du menu ne sont à
  personne. Sur un look reçu, les vêtements passent avant le corps, pour que le proxy soit habillé
  dès que les trois sont là. Un échec de lecture est dit une fois (`warnOnce`), pas une fois par
  seconde.
- **Serveur.** L'identifiant vient de la connexion ; la forme est vérifiée, jamais la vérité. Un
  client ne peut décrire que son propre joueur, la confiance que le paquet de la plateforme accorde
  aussi. Un corps hors des bornes de la plateforme (famille, 1 à 64 groupes, hachages fixes, 49 Kio)
  est refusé entier, **et répondu**, puisque renvoyer le même corps illisible toutes les trois
  secondes n'aide personne ; un vêtement illisible devient un emplacement vide, pour qu'un chapeau
  ne coûte pas son corps au joueur. Le propriétaire ne reçoit jamais son propre look : les relais de
  la plateforme ignorent leur joueur, dont le look est celui du moteur. `deliver` n'écrit pas
  `absent and false or look`, qui relirait le look chaque fois que le corps est absent. `FLOOR_MS`
  borne publications et rejeux par joueur ; le client retente quand personne n'a répondu, donc une
  demande jetée coûte des secondes, pas un look.
- **Buckets.** Le roster natif retire les répliques d'un joueur qui change de bucket de routage,
  et rien de ce que le moteur réplique ne les reconstruit : sur `onPlayerBucketChange`, le joueur et
  ceux du bucket reçoivent de nouveau le look de l'autre, sauf si un déplacement plus récent a
  remplacé celui-ci ou si le joueur est parti.
- **Redémarrage.** Rien ne survit côté serveur : `onResourceStart` envoie `:resend`, et chaque
  client déjà dans le monde publie et redemande.

Les deux moitiés se retirent, avec une ligne de journal, pendant qu'`open77_appearance` tourne :
deux resources d'apparence se disputent le bootstrap et le visage. `PRESENT_BODIES = false` les
coupe pour un serveur où une autre resource distribue les looks.

## Une fonction qui cède la main doit pouvoir renoncer

- `State.restoreToken` / `restoreSettledToken` : chaque restauration (`BeginRestore`,
  `BeginPristine`) prend une génération par `State.NextRestore` ; un thread qui tient un jeton plus
  ancien a été remplacé et s'arrête (`State.Current`). `adoptCharacter` et `State.Unload` en prennent une
  nouvelle et la marquent réglée : un changement de personnage ou un déchargement remplace une
  restauration en route, qui sinon attendrait le monde et appliquerait le visage du personnage
  parti (ou publierait un `restored` en échec sans personnage). La marquer réglée est voulu : un
  jeton laissé derrière rendrait `AppearanceSettled` faux pour toujours.
- `session` dans `client/panel.lua` : un thread du panneau (ouverture, redessin, ligne d'état,
  surveillance) compare la session qu'il a lue.
- `citizen` capturé par `openCreator` et `wearStored` : l'attente s'arrête si le personnage change.
- `sequence` dans `client/presence.lua` : une réponse (`presentAck`, `replayed`) n'est prise que pour
  la dernière demande.

Les deux boucles passent chaque appel par son propre `pcall` : une levée d'un appel hôte
terminerait sinon la boucle pour la session, ou arrêterait les appels suivants, et c'est la boucle
de `client/editor.lua` qui termine un rechargement et lève le hold de la plateforme.

## Pourquoi un visage stocké est refusé après une mise à jour

Un snapshot n'est pas un mesh : c'est une liste d'indices dans le catalogue de personnalisation.
`GAME_BUILDS` nomme les builds dans lesquels un visage peut être relu ; un visage d'un autre build
n'est pas appliqué, puisqu'il mettrait un autre visage au lieu d'échouer. `Snapshot.ForNetwork`
met les noms d'option en minuscules ici comme dans le core, pour que `Snapshot.Same` compare une
capture à un visage que le core a déjà canonisé ; il ne garde que les quatre champs qui sont le
visage, sans les métadonnées d'éditeur que le codec de valeurs du runtime ne transporte pas.

## Clés résolues à l'exécution

- `Locale.Exists(code)`, dans le gestionnaire `opx77:client:refused` de `client/editor.lua`,
  affiche un refus de `saveAppearance` dans la langue du joueur : `appearance.invalid`, `appearance.tooLarge`, `error.badRequest`,
  `error.notLoggedIn`, `error.tooFast`, `error.unavailable`. Le core mappe une panne de stockage
  sur `error.unavailable` avant de l'envoyer.
- Les refus de `saveClothing` (`clothing.invalid`, `clothing.tooLarge`, `clothing.stale`...) ne
  sont pas des clés : ils ne sont jamais affichés, seulement publiés comme `error` de
  `clothingSaved` et journalisés.

## Limites connues

- **Cache de chargement.** Sur `open77-server-2.31.13+op77.63`, le cache OPEN//77 que l'hôte pose
  pour la transition couverte d'un rechargement de corps n'est retiré par rien : `open77_shell` ne le
  lève que pour le chargement pristine de la connexion. Un joueur qui choisit un personnage de
  l'autre corps peut rester derrière ; aucune resource ne peut le lever.
- **Pas de garde-robe de visages.** Le core stocke un seul visage par personnage ; plusieurs looks
  enregistrés demandent une table et un travail côté core.
- **Pas de choix de tenue** : il faudrait un catalogue de vêtements avec des libellés, qu'aucune
  resource ne publie (`outfitsItems` dans `client/panel.lua`).
- **Horloge figée.** `nowMs` garde sa dernière lecture quand `Open77.time.monotonic` échoue : tous
  les délais du fichier en dépendent, et un commit pourrait ne jamais expirer.
