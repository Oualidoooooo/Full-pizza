# AlertesPro – alertes de trading pour MetaTrader 5

Un robot (Expert Advisor) qui tourne dans MetaTrader 5 et t'envoie des alertes
sur ton téléphone dès qu'il se passe quelque chose d'important.

## Ce qu'il surveille

| Alerte | Quand ça sonne |
|---|---|
| **Lignes de prix** | Le prix traverse une ligne horizontale que tu as tracée sur le graphique |
| **Croisement de moyennes mobiles** | La MM rapide (20) croise la MM lente (50), à la clôture de la bougie |
| **RSI** | Le RSI entre en surachat (≥ 70) ou en survente (≤ 30) |
| **Positions** | Ouverture d'une position, puis fermeture avec la raison (TP, SL, manuelle…) et le résultat |
| **Drawdown** | La perte latente dépasse 5 % du solde |
| **Marge** | Le niveau de marge descend sous 200 % |

Tout est réglable dans les paramètres du robot. Il peut surveiller plusieurs
symboles à la fois (ex. `EURUSD,XAUUSD,US30`).

## Où tu reçois les alertes

- **Fenêtre d'alerte MT5** (sur le PC)
- **Notification push** sur l'appli MetaTrader 5 de ton téléphone
- **Telegram** (via ton propre bot)
- **E-mail**
- **Son**

Un panneau en haut à gauche du graphique affiche les symboles suivis, le RSI,
le nombre de lignes actives et les dernières alertes.

## Installation (5 minutes)

1. Dans MT5 : **Fichier > Ouvrir le dossier des données**.
2. Copie `AlertesPro.mq5` dans `MQL5/Experts/`.
3. Dans MT5, ouvre **MetaEditor** (touche F4), ouvre le fichier et clique sur
   **Compiler** (F7).
4. Retourne dans MT5 : dans le **Navigateur**, fais un clic droit sur
   *Expert Advisors > Actualiser*, puis glisse **AlertesPro** sur un graphique.
5. Active le bouton **Algo Trading** en haut de MT5.

Un message de test « AlertesPro démarré… » doit arriver sur tous les canaux
activés. Sinon, regarde l'onglet **Experts** en bas de MT5 : le robot y
explique ce qui manque.

## Recevoir les alertes sur ton téléphone

### Notifications push (le plus simple)

1. Installe l'appli **MetaTrader 5** sur ton téléphone.
2. Dans l'appli : **Paramètres > Messages** (ou *Chat et messages*) → copie ton
   **MetaQuotes ID**.
3. Sur le PC : **Outils > Options > Notifications** → coche *Activer les
   notifications push* et colle ton MetaQuotes ID → **Test**.

### Telegram

1. Dans Telegram, parle à **@BotFather** → `/newbot` → note le **token**.
2. Envoie un message à ton nouveau bot, puis ouvre
   `https://api.telegram.org/bot<TON_TOKEN>/getUpdates` dans un navigateur :
   le nombre après `"chat":{"id":` est ton **chat id**.
3. Dans MT5 : **Outils > Options > Expert Advisors** → coche *Autoriser
   WebRequest* et ajoute `https://api.telegram.org`.
4. Dans les paramètres du robot : `Telegram = true`, colle le token et le chat id.

## Utiliser les lignes de prix

1. Trace une **ligne horizontale** sur le graphique où tourne le robot.
2. Double-clique dessus et renomme-la pour qu'elle commence par `ALERTE`
   (ex. `ALERTE resistance`).
3. Quand le prix la traverse, tu reçois l'alerte et la ligne devient **grise en
   pointillés** : elle ne sonnera plus.
4. Pour la réactiver : ouvre ses propriétés et efface la description
   `[déclenchée]`.

Les lignes ne marchent que pour le symbole du graphique. Pour plusieurs
symboles, place le robot sur un graphique par symbole.

## Bon à savoir

- MT5 doit rester **ouvert** (PC allumé) pour que le robot surveille le marché.
  Pour être tranquille 24 h/24, utilise un **VPS** (MT5 en propose un dans
  l'onglet *VPS*).
- Le robot **ne passe aucun ordre** : il ne fait que surveiller et prévenir.
- MetaQuotes limite les push à environ 10 par minute ; l'anti-spam du robot
  évite d'envoyer deux fois la même alerte trop vite.
- Les alertes MM et RSI sont calculées sur la bougie **clôturée**, pour éviter
  les faux signaux en cours de bougie.
