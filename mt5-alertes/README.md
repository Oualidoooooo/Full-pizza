# AlertesPro – alertes de trading pour MetaTrader 5

Un robot (Expert Advisor) qui tourne dans MetaTrader 5, surveille plusieurs
marchés et t'envoie sur ton téléphone des **signaux complets** : entrée,
stop loss, take profit et taille de lot calculée selon ton risque.

> Le robot **ne passe aucun ordre** : il analyse et il prévient, c'est toi qui
> décides. Aucune stratégie ne garantit des bénéfices. Teste d'abord sur un
> **compte démo** (voir plus bas).

## L'appli sur ton téléphone

**Lien : https://oualidoooooo.github.io/Full-pizza/mt5-alertes/app/**
(le lien marche une fois les fichiers sur la branche publiée par GitHub Pages)

Elle affiche en direct :

- **Accueil** : équité, résultat du jour, marge, positions ouvertes, dernier
  signal, annonces à venir, calculatrice de lot et règles de risque.
- **Signaux** : ton **bilan** (taux de réussite, résultat en R, facteur de
  profit, courbe), puis chaque signal avec entrée, stop, objectif (touche un
  prix pour le copier), lot, risque, son **statut** (en cours, TP touché, SL
  touché, expiré) et un bouton **Copier l'ordre**.
- **Marchés** : tendance, prix, **mini-graphique et variation sur 24 h**, jauge
  RSI, volatilité et annonce proche, ainsi que le résumé du matin.
- **Alertes** : tout l'historique, filtrable par type (dont les résultats).
- **Calculatrice** : préréglages par marché, remplissage avec le dernier signal
  ou ton solde.

À la première ouverture, elle démarre en **mode démo** avec des données
d'exemple. Pour la brancher sur ton robot :

1. Dans l'appli, ouvre **Réglages**, puis touche **Nouveau code** et **Copier**.
2. Dans MT5 : **Outils > Options > Expert Advisors** → *Autoriser WebRequest*
   → ajoute `https://ntfy.sh`.
3. Dans les paramètres du robot, colle le code dans **Appli : code de connexion**.
4. Dans l'appli, touche **Se connecter**.
5. Installe-la : sur iPhone avec **Partager > Sur l'écran d'accueil**, sur
   Android avec **⋮ > Installer l'application**.

**Pour recevoir les signaux même appli fermée** : installe l'appli gratuite
**ntfy** (App Store / Play Store), touche **+** et abonne-toi à ton code
(serveur `ntfy.sh`). Ou active Telegram dans le robot (voir plus bas).

Les données passent par **ntfy.sh**, un relais de messages gratuit et sans
inscription. Ton code sert de mot de passe : garde-le pour toi. Le relais garde
les messages 12 h et l'appli conserve l'historique sur ton téléphone. Le
compte et les marchés sont mis à jour toutes les 15 min (réglable).

## Les signaux de trading

Un signal n'est envoyé que si **toutes** les conditions sont réunies :

1. **Tendance** : prix au-dessus de l'EMA 200 → on cherche seulement des achats.
   Prix en dessous → seulement des ventes. On ne trade pas à contre-courant.
   La tendance doit être **la même en H4** (unité supérieure, réglable) et
   assez **forte** (ADX ≥ 20).
2. **Déclencheur** (à la clôture de la bougie) :
   - croisement de la MM 20 et de la MM 50 dans le sens de la tendance, ou
   - RSI qui ressort de la survente (achat) ou du surachat (vente) dans le sens
     de la tendance : on entre sur un repli, pas au sommet.
3. **Pas d'annonce économique forte** 30 min avant ou après (NFP, taux de la
   Fed, BCE, inflation…), lue dans le calendrier intégré à MT5.
4. **Spread raisonnable** par rapport à la volatilité.
5. **Un seul signal à la fois par marché** : le robot attend que le précédent
   touche son TP, son SL ou expire.

### Comment se passe un signal

1. **⏳ Pré-alerte, 1 min avant la clôture de la bougie** : un signal est en
   train de se former. Ouvre MT5 sur le marché indiqué. Si, à la clôture, les
   conditions ne sont plus réunies, tu reçois « Pré-alerte annulée ».
2. **🟢 / 🔴 Signal** à la clôture : tout ce qu'il faut pour passer l'ordre
   tout de suite. Il reste valable 15 minutes (réglable).
3. **✅ / ❌ Résultat** quand le Take Profit ou le Stop Loss est touché.

Personne ne peut connaître le marché à l'avance : la pré-alerte annonce un
signal probable, pas certain. C'est pour ça qu'on attend la confirmation.

Exemple de signal :

```
🟢 ACHAT EURUSD MAINTENANT (H1)
Entrée 1.08512 | SL 1.08197 | TP 1.09142 | Lot 0.31
À prendre avant 14:15

👉 QUOI FAIRE DANS MT5
1. Cotations > EURUSD > Nouvel ordre
2. Exécution au marché, volume 0.31
3. Stop Loss : 1.08197
4. Take Profit : 1.09142
5. Touche ACHETER (Buy)

💰 CE QUE TU RISQUES
Stop Loss touché : -97.65 EUR (1.0 % du compte)
Take Profit touché : +195.30 EUR (2.0 fois le risque)

📍 LES PRIX
Entrée : 1.08512 (prix actuel)
Stop Loss : 1.08197 (31.5 pips plus bas)
Take Profit : 1.09142 (63.0 pips plus haut)

❓ POURQUOI
- MM20 / MM50 : croisement à la hausse
- Prix au-dessus de l'EMA 200 (tendance haussière)
- Tendance haussière confirmée en H4
- Tendance forte (ADX 27)

⚠️ N'achète pas si le prix est déjà au-dessus de 1.08575 : le signal est passé.
Ne déplace jamais ton Stop Loss.
Je te préviens quand le TP ou le SL est touché.
```

Les 3 premières lignes contiennent l'essentiel : c'est ce que tu vois dans une
notification push (limitée à 255 caractères). Le message complet arrive sur
Telegram et dans l'appli.

### Comment sont calculés le stop, l'objectif et le lot

- **Stop loss = 1,5 × ATR** : l'ATR mesure combien le marché bouge en ce moment.
  Le stop s'élargit quand le marché est agité et se resserre quand il est calme,
  pour ne pas être sorti par du simple bruit.
- **Take profit = 2 × le stop** : tu vises 2 fois ce que tu risques. Avec ce
  ratio, gagner 1 trade sur 3 suffit presque à ne pas perdre d'argent (hors
  frais).
- **Lot** : calculé pour que, si le stop est touché, tu perdes **1 % de ton
  solde**, pas plus. Si même le lot minimum dépasse ce risque, le robot te dit
  de passer ton tour.

## Le suivi des résultats

Chaque signal est suivi jusqu'à sa conclusion :

- **TP touché** (+2 R), **SL touché** (−1 R) ou **expiré** après 48 bougies
  (clôturé au prix du moment).
- Tu reçois un message à chaque conclusion, avec le bilan à jour.
- Le bilan est sauvegardé dans `MQL5/Files/AlertesPro_journal.csv` : il survit
  aux redémarrages. Si MT5 était fermé, le robot rattrape au démarrage les TP et
  SL touchés pendant la coupure (grâce à l'historique M1).
- **R** = le montant risqué sur un signal. Avec 1 % de risque, +10 R ≈ +10 %
  du compte.

Le bilan s'affiche dans l'appli (onglet Signaux), sur le graphique MT5 et dans
le résumé du matin.

## Ce qu'il surveille en plus

| Alerte | Quand ça sonne |
|---|---|
| **Annonces économiques** | 30 min avant une annonce à fort impact sur une devise que tu suis |
| **Résumé du matin** | 8 h, du lundi au vendredi : tendance, RSI, volatilité de chaque marché et annonces fortes du jour |
| **Lignes de prix** | Le prix traverse une ligne horizontale que tu as tracée |
| **Positions** | Ouverture, puis fermeture avec la raison (TP, SL, manuelle) et le résultat |
| **Position sans stop** | Une position est ouverte depuis 2 min sans stop loss |
| **Perte du jour** | Tu as perdu 3 % sur la journée → le robot te dit d'arrêter |
| **Drawdown / marge** | Perte latente ≥ 5 % du solde, ou niveau de marge ≤ 200 % |
| **Alertes simples** | Tout croisement MM ou RSI 70/30, sans filtre (désactivées par défaut) |

Tous les réglages se trouvent dans les paramètres du robot.

## Les règles qui protègent ton compte

- **Toujours un stop loss**, placé dès l'entrée. Ne le recule jamais.
- **1 % de risque par trade maximum** (2 % au grand maximum). Avec 1 %, il faut
  plus de 20 pertes d'affilée pour perdre 20 % du compte.
- **Stop pour la journée** après 3 % de perte : on ne cherche pas à « se refaire ».
- **Pas de trade juste avant une annonce forte.**
- **Pas trop de positions en même temps** sur la même devise : EURUSD et GBPUSD
  à l'achat, c'est presque deux fois le même pari contre le dollar.
- Un signal n'est pas une obligation : si le graphique ne te plaît pas, passe.

## Tester avant de risquer de l'argent

1. **Testeur de stratégie** (Ctrl+R dans MT5) : choisis AlertesPro, un symbole,
   H1, une période de 1 à 2 ans, mode « Chaque tick basé sur les ticks réels ».
   Les signaux apparaissent dans le journal du testeur (le calendrier
   économique n'y est pas disponible). À la fin du test, le robot écrit un
   **BILAN ALERTESPRO** : nombre de signaux, pourcentage gagnant, total en R
   et facteur de profit. Si le total est négatif sur 1 à 2 ans, retire ce
   marché de la liste.
2. **Compte démo** pendant au moins 1 mois : prends chaque signal comme si
   c'était de l'argent réel et note les résultats.
3. Passe en réel avec un petit capital seulement si les résultats en démo sont
   bons sur au moins 30 à 50 trades.

## Installation (5 minutes)

1. Dans MT5 : **Fichier > Ouvrir le dossier des données**.
2. Copie `AlertesPro.mq5` dans `MQL5/Experts/`.
3. Ouvre **MetaEditor** (F4), ouvre le fichier et clique sur **Compiler** (F7).
4. Dans le **Navigateur** de MT5 : clic droit sur *Expert Advisors >
   Actualiser*, puis glisse **AlertesPro** sur un graphique.
5. Dans l'onglet **Paramètres**, mets tes marchés dans *Symboles*, avec les noms
   exacts de ton courtier (ex. `EURUSD,GBPUSD,USDJPY,XAUUSD,US30`). Certains
   courtiers ajoutent un suffixe, comme `EURUSDm` ou `EURUSD.pro`.
6. Active le bouton **Algo Trading** en haut de MT5.

Un message de test « AlertesPro démarré… » doit arriver sur tous les canaux
activés. Sinon, regarde l'onglet **Experts** en bas de MT5 : le robot y
explique ce qui manque.

## Recevoir les alertes sur ton téléphone

### Notifications push

1. Installe l'appli **MetaTrader 5** sur ton téléphone.
2. Dans l'appli : **Paramètres > Messages** → copie ton **MetaQuotes ID**.
3. Sur le PC : **Outils > Options > Notifications** → coche *Activer les
   notifications push*, colle ton MetaQuotes ID et clique sur **Test**.

Les notifications push sont coupées à 255 caractères. Pour lire le résumé du
matin en entier, utilise Telegram.

### Telegram (conseillé : messages complets)

1. Dans Telegram, parle à **@BotFather** → `/newbot` → note le **token**.
2. Envoie un message à ton nouveau bot, puis ouvre
   `https://api.telegram.org/bot<TON_TOKEN>/getUpdates` dans un navigateur :
   le nombre après `"chat":{"id":` est ton **chat id**.
3. Dans MT5 : **Outils > Options > Expert Advisors** → coche *Autoriser
   WebRequest* et ajoute `https://api.telegram.org`.
4. Dans les paramètres du robot : `Telegram = true`, puis colle le token et le chat id.

## Utiliser les lignes de prix

1. Trace une **ligne horizontale** sur le graphique où tourne le robot.
2. Double-clique dessus et renomme-la pour que son nom commence par `ALERTE`
   (ex. `ALERTE resistance`).
3. Quand le prix la traverse, tu reçois l'alerte et la ligne devient **grise en
   pointillés** : elle ne sonnera plus.
4. Pour la réactiver : ouvre ses propriétés et efface la description
   `[déclenchée]`.

## Bon à savoir

- MT5 doit rester **ouvert** pour que le robot surveille le marché. Pour être
  couvert 24 h/24, utilise un **VPS** (MT5 en propose un dans l'onglet *VPS*).
- Les signaux sont calculés sur la bougie **clôturée** pour éviter les faux
  signaux en cours de bougie. En H1, tu reçois donc au plus un signal par heure
  et par marché.
- MetaQuotes limite les push à environ 10 par minute ; l'anti-spam du robot
  évite les doublons.
