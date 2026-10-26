//+------------------------------------------------------------------+
//|                                                  AlertesPro.mq5  |
//|  Robot d'alertes de trading pour MetaTrader 5                     |
//|  - Lignes de prix tracées sur le graphique                        |
//|  - Croisement de moyennes mobiles                                 |
//|  - RSI en zone de surachat / survente                             |
//|  - Ouverture / fermeture de positions                             |
//|  - Drawdown et niveau de marge du compte                          |
//|  Canaux : fenêtre MT5, son, push mobile MT5, e-mail, Telegram     |
//+------------------------------------------------------------------+
#property copyright "AlertesPro"
#property version   "1.00"
#property description "Alertes de trading : lignes de prix, croisement MM, RSI, positions, drawdown."
#property description "Envoi vers la fenêtre MT5, le téléphone (push), l'e-mail et Telegram."

//--- Canaux d'envoi
input group "1. Où recevoir les alertes"
input bool   InpPopup        = true;          // Fenêtre d'alerte MT5
input bool   InpSound        = false;         // Jouer un son
input string InpSoundFile    = "alert.wav";   // Fichier son (dossier Sounds de MT5)
input bool   InpPush         = true;          // Notification push (appli MT5 mobile)
input bool   InpEmail        = false;         // E-mail (à configurer dans Outils > Options)
input bool   InpTelegram     = false;         // Telegram
input string InpTgToken      = "";            // Telegram : token du bot
input string InpTgChatId     = "";            // Telegram : chat id
input bool   InpTestAtStart  = true;          // Envoyer un message de test au démarrage

//--- Symboles surveillés
input group "2. Symboles surveillés"
input string          InpSymbols   = "";            // Symboles séparés par des virgules (vide = symbole du graphique)
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;     // Unité de temps des indicateurs

//--- Lignes de prix
input group "3. Lignes de prix sur le graphique"
input bool   InpLineAlerts   = true;          // Alerter quand le prix touche une ligne
input string InpLinePrefix   = "ALERTE";      // Les lignes horizontales dont le nom commence par ce mot

//--- Croisement de moyennes mobiles
input group "4. Croisement de moyennes mobiles"
input bool           InpMaAlerts = true;      // Activer
input int            InpMaFast   = 20;        // Période MM rapide
input int            InpMaSlow   = 50;        // Période MM lente
input ENUM_MA_METHOD InpMaMethod = MODE_EMA;  // Type de moyenne

//--- RSI
input group "5. RSI"
input bool   InpRsiAlerts    = true;          // Activer
input int    InpRsiPeriod    = 14;            // Période
input double InpRsiHigh      = 70.0;          // Seuil de surachat
input double InpRsiLow       = 30.0;          // Seuil de survente

//--- Compte
input group "6. Compte et positions"
input bool   InpTradeAlerts  = true;          // Alerter à l'ouverture / fermeture des positions
input double InpMaxDrawdown  = 5.0;           // Alerte si perte latente >= X % du solde (0 = off)
input double InpMinMargin    = 200.0;         // Alerte si niveau de marge <= X % (0 = off)
input int    InpAccountPause = 30;            // Minutes entre deux alertes compte identiques

//--- Anti-spam
input group "7. Anti-spam"
input int    InpCooldownSec  = 60;            // Secondes minimum entre deux alertes identiques

//+------------------------------------------------------------------+
//| Données internes                                                  |
//+------------------------------------------------------------------+
struct SymState
  {
   string            name;
   int               hFast;
   int               hSlow;
   int               hRsi;
   datetime          lastBar;
   double            lastRsi;
  };

SymState g_syms[];
string   g_coolKeys[];
datetime g_coolTimes[];
string   g_history[];
double   g_lastBid = 0.0;
const int HISTORY_SIZE = 6;
const string DONE_TAG = "[déclenchée]";

//+------------------------------------------------------------------+
//| Petites fonctions utiles                                         |
//+------------------------------------------------------------------+
string TfName(const ENUM_TIMEFRAMES tf)
  {
   ENUM_TIMEFRAMES t = (tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : tf;
   string s = EnumToString(t);
   return StringSubstr(s, 7); // retire "PERIOD_"
  }

string Px(const string sym, const double price)
  {
   return DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
  }

string Money(const double v)
  {
   string sign = (v >= 0) ? "+" : "";
   return sign + DoubleToString(v, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
  }

//--- Évite d'envoyer la même alerte en boucle
bool CooldownOk(const string key, const int seconds)
  {
   datetime now = TimeLocal();
   int n = ArraySize(g_coolKeys);
   for(int i = 0; i < n; i++)
     {
      if(g_coolKeys[i] == key)
        {
         if(now - g_coolTimes[i] < seconds)
            return false;
         g_coolTimes[i] = now;
         return true;
        }
     }
   ArrayResize(g_coolKeys, n + 1);
   ArrayResize(g_coolTimes, n + 1);
   g_coolKeys[n]  = key;
   g_coolTimes[n] = now;
   return true;
  }

//+------------------------------------------------------------------+
//| Telegram                                                         |
//+------------------------------------------------------------------+
string UrlEncode(const string s)
  {
   uchar bytes[];
   int n = StringToCharArray(s, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   string out = "";
   for(int i = 0; i < n; i++)
     {
      uchar c = bytes[i];
      if(c == 0)
         break;
      bool safe = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~';
      if(safe)
         out += CharToString(c);
      else
         out += StringFormat("%%%02X", c);
     }
   return out;
  }

bool SendTelegram(const string text)
  {
   if(InpTgToken == "" || InpTgChatId == "")
     {
      Print("Telegram : token ou chat id manquant.");
      return false;
     }
   string url  = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "chat_id=" + UrlEncode(InpTgChatId) + "&text=" + UrlEncode(text);
   char   post[], result[];
   string resHeaders;
   StringToCharArray(body, post, 0, StringLen(body));
   ResetLastError();
   int code = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n",
                         5000, post, result, resHeaders);
   if(code == -1)
     {
      int err = GetLastError();
      if(err == 4014)
         Print("Telegram : ajoute https://api.telegram.org dans Outils > Options > Expert Advisors > WebRequest.");
      else
         Print("Telegram : erreur WebRequest ", err);
      return false;
     }
   if(code != 200)
     {
      Print("Telegram : réponse ", code, " ", CharArrayToString(result));
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Envoi d'une alerte sur tous les canaux choisis                   |
//+------------------------------------------------------------------+
void Notify(const string msg)
  {
   string stamp = TimeToString(TimeLocal(), TIME_MINUTES);
   Print("ALERTE : ", msg);

   if(InpPopup)
      Alert(msg);
   if(InpSound && !InpPopup)
      PlaySound(InpSoundFile);
   if(InpPush && !SendNotification(StringSubstr(msg, 0, 255)))
      Print("Push : échec (", GetLastError(), "). Vérifie ton MetaQuotes ID dans Outils > Options > Notifications.");
   if(InpEmail && !SendMail("Alerte MT5", msg))
      Print("E-mail : échec (", GetLastError(), "). Vérifie Outils > Options > E-mail.");
   if(InpTelegram)
      SendTelegram(msg);

   //--- historique affiché sur le graphique
   int n = ArraySize(g_history);
   if(n >= HISTORY_SIZE)
     {
      for(int i = 0; i < n - 1; i++)
         g_history[i] = g_history[i + 1];
      n--;
     }
   ArrayResize(g_history, n + 1);
   g_history[n] = stamp + "  " + msg;
   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Panneau d'information sur le graphique                           |
//+------------------------------------------------------------------+
int CountActiveLines()
  {
   int count = 0;
   int total = ObjectsTotal(0, 0, OBJ_HLINE);
   for(int i = 0; i < total; i++)
     {
      string name = ObjectName(0, i, 0, OBJ_HLINE);
      if(StringFind(name, InpLinePrefix) == 0 && ObjectGetString(0, name, OBJPROP_TEXT) != DONE_TAG)
         count++;
     }
   return count;
  }

void UpdatePanel()
  {
   string s = "AlertesPro  |  " + TfName(InpTimeframe) + "\n";
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      s += "  " + g_syms[i].name;
      if(InpRsiAlerts && g_syms[i].lastRsi > 0)
         s += "   RSI " + DoubleToString(g_syms[i].lastRsi, 1);
      s += "\n";
     }
   if(InpLineAlerts)
      s += "Lignes actives : " + IntegerToString(CountActiveLines()) + "\n";
   s += "Dernières alertes :\n";
   if(ArraySize(g_history) == 0)
      s += "  (aucune)\n";
   for(int i = ArraySize(g_history) - 1; i >= 0; i--)
      s += "  " + g_history[i] + "\n";
   Comment(s);
  }

//+------------------------------------------------------------------+
//| Lignes de prix                                                   |
//+------------------------------------------------------------------+
void CheckLines()
  {
   if(!InpLineAlerts)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0)
      return;
   if(g_lastBid <= 0)
     {
      g_lastBid = bid;
      return;
     }

   int total = ObjectsTotal(0, 0, OBJ_HLINE);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, OBJ_HLINE);
      if(StringFind(name, InpLinePrefix) != 0)
         continue;
      if(ObjectGetString(0, name, OBJPROP_TEXT) == DONE_TAG)
         continue;

      double level = ObjectGetDouble(0, name, OBJPROP_PRICE);
      bool up   = (g_lastBid < level && bid >= level);
      bool down = (g_lastBid > level && bid <= level);
      if(!up && !down)
         continue;

      Notify(_Symbol + " : prix " + (up ? "monte au-dessus de " : "descend sous ") +
             Px(_Symbol, level) + " (ligne " + name + ")");

      //--- la ligne passe en gris : elle ne sonnera plus
      ObjectSetString(0, name, OBJPROP_TEXT, DONE_TAG);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
     }
   g_lastBid = bid;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Indicateurs (sur bougies clôturées)                              |
//+------------------------------------------------------------------+
void CheckSymbol(SymState &st)
  {
   datetime bar = iTime(st.name, InpTimeframe, 0);
   if(bar == 0 || bar == st.lastBar)
      return;
   bool first = (st.lastBar == 0);
   st.lastBar = bar;

   string tf = TfName(InpTimeframe);

   //--- RSI
   if(InpRsiAlerts && st.hRsi != INVALID_HANDLE)
     {
      double r[];
      ArraySetAsSeries(r, true);
      if(CopyBuffer(st.hRsi, 0, 1, 2, r) == 2)
        {
         st.lastRsi = r[0];
         if(!first)
           {
            if(r[1] < InpRsiHigh && r[0] >= InpRsiHigh && CooldownOk(st.name + "rsiH", InpCooldownSec))
               Notify(st.name + " " + tf + " : RSI en surachat (" + DoubleToString(r[0], 1) + ")");
            if(r[1] > InpRsiLow && r[0] <= InpRsiLow && CooldownOk(st.name + "rsiL", InpCooldownSec))
               Notify(st.name + " " + tf + " : RSI en survente (" + DoubleToString(r[0], 1) + ")");
           }
        }
     }

   //--- Croisement de moyennes mobiles
   if(InpMaAlerts && !first && st.hFast != INVALID_HANDLE && st.hSlow != INVALID_HANDLE)
     {
      double f[], s[];
      ArraySetAsSeries(f, true);
      ArraySetAsSeries(s, true);
      if(CopyBuffer(st.hFast, 0, 1, 2, f) == 2 && CopyBuffer(st.hSlow, 0, 1, 2, s) == 2)
        {
         double close = iClose(st.name, InpTimeframe, 1);
         string mm = "MM" + IntegerToString(InpMaFast) + "/MM" + IntegerToString(InpMaSlow);
         if(f[1] <= s[1] && f[0] > s[0] && CooldownOk(st.name + "maUp", InpCooldownSec))
            Notify(st.name + " " + tf + " : croisement HAUSSIER " + mm + " à " + Px(st.name, close));
         if(f[1] >= s[1] && f[0] < s[0] && CooldownOk(st.name + "maDn", InpCooldownSec))
            Notify(st.name + " " + tf + " : croisement BAISSIER " + mm + " à " + Px(st.name, close));
        }
     }
  }

//+------------------------------------------------------------------+
//| Compte : drawdown et marge                                       |
//+------------------------------------------------------------------+
void CheckAccount()
  {
   int pause = MathMax(1, InpAccountPause) * 60;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(InpMaxDrawdown > 0 && balance > 0)
     {
      double dd = (balance - equity) / balance * 100.0;
      if(dd >= InpMaxDrawdown && CooldownOk("dd", pause))
         Notify("Compte : perte latente de " + DoubleToString(dd, 1) + " % (" +
                Money(equity - balance) + ")");
     }

   if(InpMinMargin > 0 && AccountInfoDouble(ACCOUNT_MARGIN) > 0)
     {
      double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml > 0 && ml <= InpMinMargin && CooldownOk("margin", pause))
         Notify("Compte : niveau de marge bas (" + DoubleToString(ml, 0) + " %)");
     }
  }

//+------------------------------------------------------------------+
//| Positions ouvertes / fermées                                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!InpTradeAlerts || trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
      return;

   long   entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long   reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string sym    = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   double vol    = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double price  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   string lots   = DoubleToString(vol, 2) + " lot";

   if(entry == DEAL_ENTRY_IN)
     {
      Notify("Position ouverte : " + (type == DEAL_TYPE_BUY ? "ACHAT " : "VENTE ") +
             sym + " " + lots + " à " + Px(sym, price));
      return;
     }

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   string why = "manuelle";
   if(reason == DEAL_REASON_TP)
      why = "Take Profit";
   else if(reason == DEAL_REASON_SL)
      why = "Stop Loss";
   else if(reason == DEAL_REASON_SO)
      why = "Stop Out";
   else if(reason == DEAL_REASON_EXPERT)
      why = "robot";

   Notify("Position fermée (" + why + ") : " + sym + " " + lots + " à " + Px(sym, price) +
          "  Résultat " + Money(profit));
  }

//+------------------------------------------------------------------+
//| Démarrage                                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpMaFast >= InpMaSlow)
     {
      Print("La MM rapide doit avoir une période plus petite que la MM lente.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRsiLow >= InpRsiHigh)
     {
      Print("Le seuil de survente doit être plus bas que le seuil de surachat.");
      return INIT_PARAMETERS_INCORRECT;
     }

   //--- liste des symboles
   string list[];
   int n = 0;
   if(StringLen(InpSymbols) > 0)
      n = StringSplit(InpSymbols, ',', list);
   if(n == 0)
     {
      ArrayResize(list, 1);
      list[0] = _Symbol;
      n = 1;
     }

   ArrayResize(g_syms, 0);
   for(int i = 0; i < n; i++)
     {
      string sym = list[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym == "")
         continue;
      if(!SymbolSelect(sym, true))
        {
         Print("Symbole introuvable chez ton courtier : ", sym);
         continue;
        }
      int k = ArraySize(g_syms);
      ArrayResize(g_syms, k + 1);
      g_syms[k].name    = sym;
      g_syms[k].lastBar = 0;
      g_syms[k].lastRsi = 0;
      g_syms[k].hFast   = InpMaAlerts  ? iMA(sym, InpTimeframe, InpMaFast, 0, InpMaMethod, PRICE_CLOSE) : INVALID_HANDLE;
      g_syms[k].hSlow   = InpMaAlerts  ? iMA(sym, InpTimeframe, InpMaSlow, 0, InpMaMethod, PRICE_CLOSE) : INVALID_HANDLE;
      g_syms[k].hRsi    = InpRsiAlerts ? iRSI(sym, InpTimeframe, InpRsiPeriod, PRICE_CLOSE) : INVALID_HANDLE;
     }

   if(ArraySize(g_syms) == 0)
     {
      Print("Aucun symbole valide.");
      return INIT_PARAMETERS_INCORRECT;
     }

   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
   EventSetTimer(1);
   UpdatePanel();

   if(InpTestAtStart && !MQLInfoInteger(MQL_TESTER))
      Notify("AlertesPro démarré sur " + IntegerToString(ArraySize(g_syms)) + " symbole(s), " +
             TfName(InpTimeframe) + ". Les alertes arriveront ici.");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      if(g_syms[i].hFast != INVALID_HANDLE) IndicatorRelease(g_syms[i].hFast);
      if(g_syms[i].hSlow != INVALID_HANDLE) IndicatorRelease(g_syms[i].hSlow);
      if(g_syms[i].hRsi  != INVALID_HANDLE) IndicatorRelease(g_syms[i].hRsi);
     }
   Comment("");
  }

//+------------------------------------------------------------------+
//| Boucles                                                          |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckLines();
  }

void OnTimer()
  {
   CheckLines();
   for(int i = 0; i < ArraySize(g_syms); i++)
      CheckSymbol(g_syms[i]);
   CheckAccount();
   UpdatePanel();
  }

//--- met à jour le panneau quand on ajoute ou supprime une ligne
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DELETE || id == CHARTEVENT_OBJECT_DRAG)
      UpdatePanel();
  }
//+------------------------------------------------------------------+
