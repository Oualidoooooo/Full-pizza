//+------------------------------------------------------------------+
//|                                                  AlertesPro.mq5  |
//|  Robot d'alertes de trading pour MetaTrader 5                     |
//|  - Signaux complets : entrée, stop loss, take profit, lot        |
//|    (filtre de tendance EMA 200, stop basé sur l'ATR)             |
//|  - Calendrier économique : prévient avant les annonces fortes    |
//|  - Résumé du marché chaque matin                                 |
//|  - Lignes de prix, croisement MM, RSI                            |
//|  - Ouverture / fermeture de positions, drawdown, marge           |
//|  - Pré-alerte 1 min avant la clôture quand un signal se prépare  |
//|  - Suivi de chaque signal jusqu'au TP, au SL ou à l'expiration,  |
//|    avec bilan (taux de réussite, résultat en R)                  |
//|  Canaux : fenêtre MT5, son, push mobile MT5, e-mail, Telegram    |
//|  Le robot ne passe AUCUN ordre : il surveille et il prévient.    |
//+------------------------------------------------------------------+
#property copyright "AlertesPro"
#property version   "1.41"
#property description "Signaux avec stop loss / take profit / lot, suivi des résultats, calendrier économique, résumé du matin."
#property description "Ne passe aucun ordre. Teste d'abord sur un compte démo."

//--- Canaux d'envoi
input group "1. Où recevoir les alertes"
input bool   InpPopup        = true;          // Fenêtre d'alerte MT5
input bool   InpSound        = false;         // Jouer un son
input string InpSoundFile    = "alert.wav";   // Fichier son (dossier Sounds de MT5)
input bool   InpPush         = true;          // Notification push (appli MT5 mobile)
input bool   InpEmail        = false;         // E-mail (à configurer dans Outils > Options)
input bool   InpTelegram     = false;         // Telegram
input string InpTgToken      = "";            // Telegram : token du bot
input string InpTgChatId     = "";            // Telegram : chat id (laisse vide : il est trouvé tout seul)
input bool   InpTestAtStart  = true;          // Envoyer un message de test au démarrage
input bool   InpApp          = true;          // Appli AlertesPro (tableau de bord sur le téléphone)
input string InpAppCode      = "";            // Appli : code de connexion (copie-le depuis l'appli)
input int    InpStatusMin    = 15;            // Appli : minutes entre deux mises à jour du compte

//--- Symboles surveillés
input group "2. Marchés surveillés"
input string          InpSymbols   = "EURUSD,GBPUSD,USDJPY,XAUUSD"; // Symboles séparés par des virgules (vide = symbole du graphique)
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;     // Unité de temps

//--- Signaux de trading
input group "3. Signaux de trading (entrée + SL + TP + lot)"
input bool   InpSignals      = true;          // Activer les signaux
input bool   InpSigCross     = true;          // Signal : croisement MM dans le sens de la tendance
input bool   InpSigPullback  = true;          // Signal : RSI qui rebondit dans le sens de la tendance
input int    InpTrendPeriod  = 200;           // Filtre de tendance : période de l'EMA
input int    InpAtrPeriod    = 14;            // Période ATR (volatilité)
input double InpAtrMult      = 1.5;           // Stop loss = ATR x ce nombre
input double InpRR           = 2.0;           // Take profit = stop x ce nombre (ratio gain/risque)
input double InpRiskPct      = 1.0;           // Risque par trade en % du solde
input double InpMaxSpreadAtr = 0.25;          // Pas de signal si spread > ATR x ce nombre
input bool   InpHtfFilter    = true;          // Confirmer la tendance sur une unité de temps supérieure
input ENUM_TIMEFRAMES InpHtf = PERIOD_H4;     // Unité de temps supérieure (même EMA de tendance)
input double InpAdxMin       = 20.0;          // Force de tendance minimale (ADX), 0 = pas de filtre
input bool   InpOnePerSymbol = true;          // Un seul signal à la fois par marché (attend TP, SL ou expiration)
input bool   InpPreAlert     = true;          // Pré-alerte juste avant la clôture de la bougie
input int    InpPreAlertSec  = 60;            // Secondes avant la clôture pour la pré-alerte
input int    InpValidMin     = 15;            // Minutes pendant lesquelles un signal reste bon à prendre

//--- Suivi des résultats
input group "3b. Suivi des résultats"
input bool   InpTrack        = true;          // Suivre chaque signal jusqu'au TP, au SL ou à l'expiration
input int    InpExpireBars   = 48;            // Expiration d'un signal non résolu (en bougies)
input bool   InpResultAlerts = true;          // Prévenir quand un signal touche son TP ou son SL

//--- Calendrier économique
input group "4. Annonces économiques"
input bool   InpNewsAlerts   = true;          // Prévenir avant une annonce à fort impact
input int    InpNewsBefore   = 30;            // Minutes avant l'annonce
input bool   InpNewsBlock    = true;          // Pas de signal autour d'une annonce forte
input int    InpNewsWindow   = 30;            // Fenêtre de blocage (minutes avant et après)

//--- Résumé quotidien
input group "5. Résumé du marché"
input bool   InpSummary      = true;          // Envoyer un résumé chaque jour de semaine
input int    InpSummaryHour  = 8;             // Heure du résumé (heure de ton PC)

//--- Lignes de prix
input group "6. Lignes de prix sur le graphique"
input bool   InpLineAlerts   = true;          // Alerter quand le prix touche une ligne
input string InpLinePrefix   = "ALERTE";      // Les lignes horizontales dont le nom commence par ce mot

//--- Alertes simples
input group "7. Alertes simples (sans filtre)"
input bool           InpMaAlerts  = false;    // Tout croisement de MM
input int            InpMaFast    = 20;       // Période MM rapide
input int            InpMaSlow    = 50;       // Période MM lente
input ENUM_MA_METHOD InpMaMethod  = MODE_EMA; // Type de moyenne
input bool           InpRsiAlerts = false;    // RSI en surachat / survente
input int            InpRsiPeriod = 14;       // Période RSI
input double         InpRsiHigh   = 70.0;     // Seuil de surachat
input double         InpRsiLow    = 30.0;     // Seuil de survente

//--- Compte
input group "8. Compte et positions"
input bool   InpTradeAlerts  = true;          // Alerter à l'ouverture / fermeture des positions
input bool   InpNoStopAlert  = true;          // Alerter si une position n'a pas de stop loss
input double InpMaxDrawdown  = 5.0;           // Alerte si perte latente >= X % du solde (0 = off)
input double InpMinMargin    = 200.0;         // Alerte si niveau de marge <= X % (0 = off)
input double InpDailyLossPct = 3.0;           // Alerte si perte du jour >= X % du solde (0 = off)
input int    InpAccountPause = 30;            // Minutes entre deux alertes compte identiques

//--- Anti-spam
input group "9. Anti-spam"
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
   int               hTrend;
   int               hAtr;
   int               hHtf;
   int               hAdx;
   datetime          lastBar;
   double            lastRsi;
   datetime          preBar;   // bougie pour laquelle une pré-alerte est partie
  };

//--- signal suivi jusqu'à sa conclusion
struct Track
  {
   string            sid;
   string            sym;
   bool              buy;
   double            entry;
   double            sl;
   double            tp;
   datetime          opened;
  };

SymState g_syms[];
Track    g_tracks[];
int      g_statN      = 0;     // signaux terminés
int      g_statWins   = 0;     // gagnants (R > 0)
double   g_statR      = 0.0;   // somme des R
double   g_statGrossW = 0.0;   // somme des R gagnants
double   g_statGrossL = 0.0;   // somme des R perdants (valeur positive)
const string JOURNAL_FILE = "AlertesPro_journal.csv";
const string TG_FILE      = "AlertesPro_telegram.txt";
string   g_tgChat    = "";   // chat id trouvé automatiquement
datetime g_tgLastTry = 0;
string   g_coolKeys[];
datetime g_coolTimes[];
string   g_history[];
double   g_lastBid = 0.0;
int      g_lastSummaryDay = -1;
datetime g_lastNewsCheck = 0;
const int    HISTORY_SIZE = 6;
const string DONE_TAG = "[déclenchée]";

//+------------------------------------------------------------------+
//| Petites fonctions utiles                                         |
//+------------------------------------------------------------------+
string TfName(const ENUM_TIMEFRAMES tf)
  {
   ENUM_TIMEFRAMES t = (tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : tf;
   return StringSubstr(EnumToString(t), 7); // retire "PERIOD_"
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

//--- taille d'un pip (5 et 3 décimales : 10 points)
double PipSize(const string sym)
  {
   int    d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double p = SymbolInfoDouble(sym, SYMBOL_POINT);
   return (d == 3 || d == 5) ? p * 10.0 : p;
  }

string Pips(const string sym, const double dist)
  {
   double pip = PipSize(sym);
   if(pip <= 0)
      return "";
   return DoubleToString(dist / pip, 1) + " pips";
  }

int VolDigits(const string sym)
  {
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0 || step >= 1)
      return 0;
   return (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9));
  }

bool LastValue(const int handle, const int shift, double &value)
  {
   if(handle == INVALID_HANDLE)
      return false;
   double b[];
   if(CopyBuffer(handle, 0, shift, 1, b) != 1)
      return false;
   value = b[0];
   return true;
  }

bool TwoValuesAt(const int handle, const int shift, double &cur, double &prev)
  {
   if(handle == INVALID_HANDLE)
      return false;
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(handle, 0, shift, 2, b) != 2)
      return false;
   cur  = b[0]; // bougie analysée
   prev = b[1]; // celle d'avant
   return true;
  }

bool TwoValues(const int handle, double &cur, double &prev)
  {
   return TwoValuesAt(handle, 1, cur, prev); // 1 = dernière bougie clôturée
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

//--- chat id : celui des paramètres, sinon celui trouvé automatiquement
string TgChat()
  {
   string c = InpTgChatId;
   StringTrimLeft(c);
   StringTrimRight(c);
   return (c != "") ? c : g_tgChat;
  }

void TgSaveChat()
  {
   int h = FileOpen(TG_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileWriteString(h, g_tgChat);
   FileClose(h);
  }

void TgLoadChat()
  {
   if(!FileIsExist(TG_FILE))
      return;
   int h = FileOpen(TG_FILE, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   g_tgChat = FileReadString(h);
   StringTrimLeft(g_tgChat);
   StringTrimRight(g_tgChat);
   FileClose(h);
  }

//--- cherche le chat id dans les derniers messages reçus par le bot (/start)
bool TgFindChat()
  {
   static bool told = false;
   if(InpTgToken == "" || MQLInfoInteger(MQL_TESTER))
      return false;
   char   post[], result[];
   string resHeaders;
   ResetLastError();
   int code = WebRequest("GET", "https://api.telegram.org/bot" + InpTgToken + "/getUpdates", "",
                         5000, post, result, resHeaders);
   if(code == -1)
     {
      if(GetLastError() == 4014 && !told)
        {
         Print("Telegram : ajoute https://api.telegram.org dans Outils > Options > Expert Advisors > WebRequest.");
         told = true;
        }
      return false;
     }
   if(code == 401 || code == 404)
     {
      if(!told)
         Print("Telegram : jeton refusé. Recopie le token donné par @BotFather.");
      told = true;
      return false;
     }
   if(code != 200)
      return false;
   string json = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   string key  = "\"chat\":{\"id\":";
   int p = StringFind(json, key);
   if(p < 0)
     {
      if(!told)
         Print("Telegram : envoie /start à ton bot dans Telegram, je trouverai ton chat id tout seul.");
      told = true;
      return false;
     }
   p += StringLen(key);
   string id = "";
   int n = StringLen(json);
   while(p < n)
     {
      ushort c = StringGetCharacter(json, p);
      if((c >= '0' && c <= '9') || c == '-')
        {
         id += ShortToString(c);
         p++;
        }
      else
         break;
     }
   if(id == "")
      return false;
   g_tgChat = id;
   TgSaveChat();
   Print("Telegram : chat id trouvé (", id, ").");
   return true;
  }

//--- tant que le chat id manque : réessaie toutes les 20 secondes
void CheckTelegram()
  {
   if(!InpTelegram || InpTgToken == "" || TgChat() != "" || MQLInfoInteger(MQL_TESTER))
      return;
   if(TimeLocal() - g_tgLastTry < 20)
      return;
   g_tgLastTry = TimeLocal();
   if(TgFindChat())
      SendTelegram("✅ AlertesPro : Telegram est connecté.\nTes pré-alertes, signaux et résultats arriveront ici.");
  }

bool SendTelegram(const string text)
  {
   if(InpTgToken == "")
     {
      Print("Telegram : colle le token de ton bot dans les paramètres du robot.");
      return false;
     }
   if(TgChat() == "")
     {
      Print("Telegram : chat id pas encore trouvé. Envoie /start à ton bot dans Telegram.");
      return false;
     }
   string url  = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "chat_id=" + UrlEncode(TgChat()) + "&text=" + UrlEncode(text);
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
//| Appli AlertesPro (relais ntfy.sh)                                |
//+------------------------------------------------------------------+
string JsonEscape(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\r", "");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\t", " ");
   return s;
  }

//--- tags = "cle=valeur,cle=valeur" (données lues par l'appli)
bool SendApp(const string kind, const string title, const string msg, const string tags, const int priority = 3)
  {
   if(!InpApp || InpAppCode == "" || MQLInfoInteger(MQL_TESTER))
      return false;
   string list[];
   int n = StringSplit("k=" + kind + (tags == "" ? "" : "," + tags), ',', list);
   string jt = "";
   for(int i = 0; i < n; i++)
     {
      if(list[i] == "")
         continue;
      jt += (jt == "" ? "" : ",") + "\"" + JsonEscape(list[i]) + "\"";
     }
   string body = "{\"topic\":\"" + JsonEscape(InpAppCode) + "\"," +
                 "\"title\":\"" + JsonEscape(title) + "\"," +
                 "\"message\":\"" + JsonEscape(msg) + "\"," +
                 "\"priority\":" + IntegerToString(priority) + "," +
                 "\"tags\":[" + jt + "]}";
   char post[], result[];
   string resHeaders;
   int len = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0)
      ArrayResize(post, len - 1); // retire le zéro final
   ResetLastError();
   int code = WebRequest("POST", "https://ntfy.sh/", "Content-Type: application/json\r\n",
                         5000, post, result, resHeaders);
   if(code == -1)
     {
      int err = GetLastError();
      if(err == 4014)
         Print("Appli : ajoute https://ntfy.sh dans Outils > Options > Expert Advisors > WebRequest.");
      else
         Print("Appli : erreur WebRequest ", err);
      return false;
     }
   if(code != 200)
     {
      Print("Appli : réponse ", code, " ", CharArrayToString(result));
      return false;
     }
   return true;
  }

//--- état du compte et des marchés pour le tableau de bord
void SendStatus()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double closed  = TodayClosedProfit();
   string tags = "bal=" + DoubleToString(balance, 2) +
                 ",eq=" + DoubleToString(equity, 2) +
                 ",cur=" + AccountInfoString(ACCOUNT_CURRENCY) +
                 ",day=" + DoubleToString(closed + equity - balance, 2) +
                 ",ml=" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN) > 0 ? AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) : 0, 0) +
                 ",pos=" + IntegerToString(PositionsTotal()) +
                 ",tf=" + TfName(InpTimeframe) +
                 ",risk=" + DoubleToString(InpRiskPct, 1) +
                 "," + StatsTag();
   for(int i = 0; i < ArraySize(g_tracks) && i < 10; i++)
     {
      int dg = (int)SymbolInfoInteger(g_tracks[i].sym, SYMBOL_DIGITS);
      tags += ",o=" + g_tracks[i].sid + "|" + g_tracks[i].sym + "|" + (g_tracks[i].buy ? "buy" : "sell") + "|" +
              DoubleToString(g_tracks[i].entry, dg) + "|" + DoubleToString(g_tracks[i].sl, dg) + "|" +
              DoubleToString(g_tracks[i].tp, dg);
     }
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      string sym = g_syms[i].name;
      double trend = 0, atr = 0, rsi = 0;
      double close = iClose(sym, InpTimeframe, 1);
      string dir = "?";
      if(LastValue(g_syms[i].hTrend, 1, trend) && close > 0)
         dir = (close > trend) ? "up" : "down";
      LastValue(g_syms[i].hRsi, 1, rsi);
      LastValue(g_syms[i].hAtr, 1, atr);
      string news = "";
      bool hasNews = NewsNear(sym, 60, news);
      tags += ",m=" + sym + "|" + dir + "|" + DoubleToString(rsi, 1) + "|" +
              DoubleToString(PipSize(sym) > 0 ? atr / PipSize(sym) : 0, 1) + "|" +
              Px(sym, SymbolInfoDouble(sym, SYMBOL_BID)) + "|" + (hasNews ? "1" : "0");
     }
   for(int i = 0; i < PositionsTotal() && i < 10; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      tags += ",p=" + sym + "|" +
              (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "buy" : "sell") + "|" +
              DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + "|" +
              DoubleToString(PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP), 2) + "|" +
              (PositionGetDouble(POSITION_SL) != 0 ? "1" : "0");
     }
   SendApp("status", "Statut", "Mise à jour du compte", tags, 1);
  }

void CheckStatus()
  {
   static datetime last = 0;
   if(!InpApp || InpAppCode == "")
      return;
   if(last != 0 && TimeLocal() - last < (int)MathMax(1, InpStatusMin) * 60)
      return;
   last = TimeLocal();
   SendStatus();
  }

//+------------------------------------------------------------------+
//| Envoi d'une alerte sur tous les canaux choisis                   |
//+------------------------------------------------------------------+
void Notify(const string msg, const string kind = "info", const string tags = "")
  {
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

   //--- historique affiché sur le graphique (première ligne du message)
   string first = msg;
   int nl = StringFind(msg, "\n");
   if(nl > 0)
      first = StringSubstr(msg, 0, nl);
   SendApp(kind, first, msg, tags, kind == "signal" || kind == "account" ? 4 : 3);
   int n = ArraySize(g_history);
   if(n >= HISTORY_SIZE)
     {
      for(int i = 0; i < n - 1; i++)
         g_history[i] = g_history[i + 1];
      n--;
     }
   ArrayResize(g_history, n + 1);
   g_history[n] = TimeToString(TimeLocal(), TIME_MINUTES) + "  " + first;
   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Calendrier économique (données intégrées à MT5)                  |
//+------------------------------------------------------------------+
//--- devises d'un symbole (ex. EURUSD -> EUR et USD)
int SymbolCurrencies(const string sym, string &cur[])
  {
   ArrayResize(cur, 0);
   string a = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE);
   string b = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
   if(a != "")
     {
      ArrayResize(cur, 1);
      cur[0] = a;
     }
   if(b != "" && b != a)
     {
      int n = ArraySize(cur);
      ArrayResize(cur, n + 1);
      cur[n] = b;
     }
   return ArraySize(cur);
  }

//--- vrai si une annonce forte tombe entre from et to pour cette devise
bool FindHighNews(const string currency, const datetime from, const datetime to,
                  MqlCalendarValue &found, string &eventName)
  {
   MqlCalendarValue vals[];
   if(CalendarValueHistory(vals, from, to, NULL, currency) <= 0)
      return false;
   for(int i = 0; i < ArraySize(vals); i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      found     = vals[i];
      eventName = ev.name;
      return true;
     }
   return false;
  }

string MinutesText(const long seconds)
  {
   long m = seconds / 60;
   if(m >= 0)
      return "dans " + IntegerToString(m) + " min";
   return "il y a " + IntegerToString(-m) + " min";
  }

//--- annonce forte proche pour ce symbole ? (texte dans label)
bool NewsNear(const string sym, const int minutes, string &label)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return false;
   string cur[];
   datetime now = TimeTradeServer();
   int nc = SymbolCurrencies(sym, cur);
   for(int c = 0; c < nc; c++)
     {
      MqlCalendarValue v;
      string name;
      if(FindHighNews(cur[c], now - minutes * 60, now + minutes * 60, v, name))
        {
         label = cur[c] + " " + name + " (" + MinutesText((long)(v.time - now)) + ")";
         return true;
        }
     }
   return false;
  }

void CheckNews()
  {
   if(!InpNewsAlerts || MQLInfoInteger(MQL_TESTER))
      return;
   if(TimeLocal() - g_lastNewsCheck < 60)
      return;
   g_lastNewsCheck = TimeLocal();

   datetime now = TimeTradeServer();
   string done = ",";
   for(int s = 0; s < ArraySize(g_syms); s++)
     {
      string cur[];
      int nc = SymbolCurrencies(g_syms[s].name, cur);
      for(int c = 0; c < nc; c++)
        {
         if(StringFind(done, "," + cur[c] + ",") >= 0)
            continue;
         done += cur[c] + ",";

         MqlCalendarValue vals[];
         if(CalendarValueHistory(vals, now, now + InpNewsBefore * 60, NULL, cur[c]) <= 0)
            continue;
         for(int i = 0; i < ArraySize(vals); i++)
           {
            MqlCalendarEvent ev;
            if(!CalendarEventById(vals[i].event_id, ev) || ev.importance != CALENDAR_IMPORTANCE_HIGH)
               continue;
            if(!CooldownOk("news" + IntegerToString((long)vals[i].id), 86400))
               continue;
            Notify("ANNONCE FORTE " + MinutesText((long)(vals[i].time - now)) + " : " +
                   cur[c] + " - " + ev.name +
                   "\nLe marché peut bouger fort. Évite d'entrer juste avant et vérifie tes stops sur " +
                   cur[c] + ".", "news", "cur=" + cur[c] + ",min=" + IntegerToString((long)(vals[i].time - now) / 60));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Gestion du risque : taille de lot                                |
//+------------------------------------------------------------------+
//--- lot pour perdre au maximum riskMoney si le stop (distance dist) est touché
double LotForRisk(const string sym, const double dist, const double riskMoney, double &realRisk)
  {
   realRisk = 0;
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double step      = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(tickSize <= 0 || tickValue <= 0 || step <= 0 || dist <= 0)
      return 0;

   double lossPerLot = dist / tickSize * tickValue;
   double lots = MathFloor(riskMoney / lossPerLot / step) * step;
   if(lots < minLot)
      return 0;
   lots = MathMin(lots, maxLot);
   realRisk = lots * lossPerLot;
   return lots;
  }

//+------------------------------------------------------------------+
//| Suivi des résultats des signaux                                  |
//+------------------------------------------------------------------+
bool HasOpenTrack(const string sym)
  {
   for(int i = 0; i < ArraySize(g_tracks); i++)
      if(g_tracks[i].sym == sym)
         return true;
   return false;
  }

string StatsTag()
  {
   return "st=" + IntegerToString(g_statN) + "|" + IntegerToString(g_statWins) + "|" +
          DoubleToString(g_statR, 2) + "|" + DoubleToString(g_statGrossW, 2) + "|" +
          DoubleToString(g_statGrossL, 2);
  }

string StatsText()
  {
   if(g_statN == 0)
      return "Bilan des signaux : aucun signal terminé pour l'instant.";
   return "Bilan des signaux : " + IntegerToString(g_statN) + " terminés, " +
          DoubleToString(100.0 * g_statWins / g_statN, 0) + " % gagnants, " +
          (g_statR >= 0 ? "+" : "") + DoubleToString(g_statR, 1) + " R au total.";
  }

//--- sauvegarde : une ligne de statistiques puis une ligne par signal ouvert
void SaveJournal()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   int h = FileOpen(JOURNAL_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      Print("Journal : écriture impossible (", GetLastError(), ").");
      return;
     }
   FileWriteString(h, "STATS;" + IntegerToString(g_statN) + ";" + IntegerToString(g_statWins) + ";" +
                   DoubleToString(g_statR, 4) + ";" + DoubleToString(g_statGrossW, 4) + ";" +
                   DoubleToString(g_statGrossL, 4) + "\r\n");
   for(int i = 0; i < ArraySize(g_tracks); i++)
     {
      int dg = (int)SymbolInfoInteger(g_tracks[i].sym, SYMBOL_DIGITS);
      FileWriteString(h, "OPEN;" + g_tracks[i].sid + ";" + g_tracks[i].sym + ";" +
                      (g_tracks[i].buy ? "buy" : "sell") + ";" +
                      DoubleToString(g_tracks[i].entry, dg) + ";" + DoubleToString(g_tracks[i].sl, dg) + ";" +
                      DoubleToString(g_tracks[i].tp, dg) + ";" + IntegerToString((long)g_tracks[i].opened) + "\r\n");
     }
   FileClose(h);
  }

void LoadJournal()
  {
   ArrayResize(g_tracks, 0);
   if(MQLInfoInteger(MQL_TESTER) || !FileIsExist(JOURNAL_FILE))
      return;
   int h = FileOpen(JOURNAL_FILE, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      string f[];
      int n = StringSplit(line, ';', f);
      if(n >= 6 && f[0] == "STATS")
        {
         g_statN      = (int)StringToInteger(f[1]);
         g_statWins   = (int)StringToInteger(f[2]);
         g_statR      = StringToDouble(f[3]);
         g_statGrossW = StringToDouble(f[4]);
         g_statGrossL = StringToDouble(f[5]);
        }
      else if(n >= 8 && f[0] == "OPEN")
        {
         int k = ArraySize(g_tracks);
         ArrayResize(g_tracks, k + 1);
         g_tracks[k].sid    = f[1];
         g_tracks[k].sym    = f[2];
         g_tracks[k].buy    = (f[3] == "buy");
         g_tracks[k].entry  = StringToDouble(f[4]);
         g_tracks[k].sl     = StringToDouble(f[5]);
         g_tracks[k].tp     = StringToDouble(f[6]);
         g_tracks[k].opened = (datetime)StringToInteger(f[7]);
        }
     }
   FileClose(h);
  }

void AddTrack(const string sid, const string sym, const bool buy, const double entry, const double sl, const double tp)
  {
   if(!InpTrack)
      return;
   int k = ArraySize(g_tracks);
   ArrayResize(g_tracks, k + 1);
   g_tracks[k].sid    = sid;
   g_tracks[k].sym    = sym;
   g_tracks[k].buy    = buy;
   g_tracks[k].entry  = entry;
   g_tracks[k].sl     = sl;
   g_tracks[k].tp     = tp;
   g_tracks[k].opened = TimeCurrent();
   SaveJournal();
  }

//--- clôture d'un signal : statistiques, message, retrait de la liste
void CloseTrack(const int idx, const string res, const double exitPx)
  {
   Track t = g_tracks[idx];
   double risk = MathAbs(t.entry - t.sl);
   double r = 0;
   if(risk > 0)
      r = (t.buy ? exitPx - t.entry : t.entry - exitPx) / risk;
   g_statN++;
   g_statR += r;
   if(r > 0)
     {
      g_statWins++;
      g_statGrossW += r;
     }
   else
      g_statGrossL += -r;

   int n = ArraySize(g_tracks);
   for(int i = idx; i < n - 1; i++)
      g_tracks[i] = g_tracks[i + 1];
   ArrayResize(g_tracks, n - 1);
   SaveJournal();

   string what = (res == "tp") ? "TAKE PROFIT TOUCHÉ" : (res == "sl") ? "STOP LOSS TOUCHÉ" : "SIGNAL EXPIRÉ";
   string side = t.buy ? "ACHAT " : "VENTE ";
   string msg = what + " : " + side + t.sym + "\n" +
                "Entrée " + Px(t.sym, t.entry) + " -> sortie " + Px(t.sym, exitPx) + "\n" +
                "Résultat " + (r >= 0 ? "+" : "") + DoubleToString(r, 2) + " R\n" + StatsText();
   string tags = "sid=" + t.sid + ",sym=" + t.sym + ",side=" + (t.buy ? "buy" : "sell") + ",res=" + res +
                 ",r=" + DoubleToString(r, 2) + ",exit=" + Px(t.sym, exitPx) + "," + StatsTag();
   if(InpResultAlerts)
      Notify(msg, "result", tags);
   else
      Print(msg);
  }

//--- un signal a-t-il touché son SL ou son TP pendant que MT5 était fermé ?
bool ResolveFromHistory(const Track &t, string &res, double &exitPx)
  {
   MqlRates rates[];
   int n = CopyRates(t.sym, PERIOD_M1, t.opened, TimeCurrent(), rates);
   if(n <= 0)
      return false;
   double point = SymbolInfoDouble(t.sym, SYMBOL_POINT);
   for(int i = 0; i < n; i++)
     {
      double spread = rates[i].spread * point;
      if(t.buy)
        {
         if(rates[i].low <= t.sl)  { res = "sl"; exitPx = t.sl; return true; }
         if(rates[i].high >= t.tp) { res = "tp"; exitPx = t.tp; return true; }
        }
      else
        {
         if(rates[i].high + spread >= t.sl) { res = "sl"; exitPx = t.sl; return true; }
         if(rates[i].low + spread <= t.tp)  { res = "tp"; exitPx = t.tp; return true; }
        }
     }
   return false;
  }

void CheckTracks()
  {
   static datetime last = 0;
   if(!MQLInfoInteger(MQL_TESTER) && TimeLocal() - last < 2)
      return;
   last = TimeLocal();
   int life = (int)MathMax(1, InpExpireBars) * PeriodSeconds(InpTimeframe);
   for(int i = ArraySize(g_tracks) - 1; i >= 0; i--)
     {
      string sym = g_tracks[i].sym;
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(bid <= 0 || ask <= 0)
         continue;
      bool buy = g_tracks[i].buy;
      double sl = g_tracks[i].sl, tp = g_tracks[i].tp;
      if(buy && bid <= sl)
         CloseTrack(i, "sl", sl);
      else if(buy && bid >= tp)
         CloseTrack(i, "tp", tp);
      else if(!buy && ask >= sl)
         CloseTrack(i, "sl", sl);
      else if(!buy && ask <= tp)
         CloseTrack(i, "tp", tp);
      else if(TimeCurrent() - g_tracks[i].opened >= life)
         CloseTrack(i, "exp", buy ? bid : ask);
     }
  }

//--- au démarrage : rattrape les TP / SL touchés pendant une coupure
void CatchUpTracks()
  {
   for(int i = ArraySize(g_tracks) - 1; i >= 0; i--)
     {
      string res;
      double exitPx;
      if(!SymbolSelect(g_tracks[i].sym, true))
         continue;
      if(ResolveFromHistory(g_tracks[i], res, exitPx))
         CloseTrack(i, res, exitPx);
     }
  }

//+------------------------------------------------------------------+
//| Construction d'un signal complet                                 |
//+------------------------------------------------------------------+
//--- reason : une raison par ligne, séparées par "\n- "
bool SendSignal(const string sym, const bool buy, const string reason, const double atr)
  {
   string tf = TfName(InpTimeframe);
   if(InpOnePerSymbol && InpTrack && HasOpenTrack(sym))
     {
      Print(sym, " : signal ignoré, le précédent signal sur ce marché est toujours en cours.");
      return false;
     }
   if(!CooldownOk(sym + (buy ? "sigB" : "sigS"), (int)MathMax(InpCooldownSec, PeriodSeconds(InpTimeframe))))
      return false;

   //--- spread trop large par rapport à la volatilité
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(ask <= 0 || bid <= 0)
      return false;
   if(InpMaxSpreadAtr > 0 && (ask - bid) > atr * InpMaxSpreadAtr)
     {
      Print(sym, " : signal ignoré, spread trop large (", Pips(sym, ask - bid), ").");
      return false;
     }

   //--- annonce économique proche
   string news;
   bool newsNear = NewsNear(sym, InpNewsWindow, news);
   if(newsNear && InpNewsBlock)
     {
      Print(sym, " : signal ignoré à cause de l'annonce ", news);
      return false;
     }

   int    dg    = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double dist  = atr * InpAtrMult;
   double entry = NormalizeDouble(buy ? ask : bid, dg);
   double sl    = NormalizeDouble(buy ? entry - dist : entry + dist, dg);
   double tp    = NormalizeDouble(buy ? entry + dist * InpRR : entry - dist * InpRR, dg);
   double limit = NormalizeDouble(buy ? entry + dist * 0.2 : entry - dist * 0.2, dg);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPct / 100.0;
   double realRisk  = 0;
   double lots      = LotForRisk(sym, dist, riskMoney, realRisk);
   string cur       = AccountInfoString(ACCOUNT_CURRENCY);
   string lotTxt    = DoubleToString(lots, VolDigits(sym));
   int    validMin  = (int)MathMax(1, InpValidMin);
   datetime until   = TimeLocal() + validMin * 60;

   //--- 3 premières lignes : l'essentiel (visible dans une notification)
   string msg = (buy ? "🟢 ACHAT " : "🔴 VENTE ") + sym + " MAINTENANT (" + tf + ")\n";
   msg += "Entrée " + Px(sym, entry) + " | SL " + Px(sym, sl) + " | TP " + Px(sym, tp);
   if(lots > 0)
      msg += " | Lot " + lotTxt;
   msg += "\nÀ prendre avant " + TimeToString(until, TIME_MINUTES) + "\n\n";

   if(lots > 0)
     {
      msg += "👉 QUOI FAIRE DANS MT5\n";
      msg += "1. Cotations > " + sym + " > Nouvel ordre\n";
      msg += "2. Exécution au marché, volume " + lotTxt + "\n";
      msg += "3. Stop Loss : " + Px(sym, sl) + "\n";
      msg += "4. Take Profit : " + Px(sym, tp) + "\n";
      msg += "5. Touche " + (buy ? "ACHETER (Buy)" : "VENDRE (Sell)") + "\n\n";
      msg += "💰 CE QUE TU RISQUES\n";
      msg += "Stop Loss touché : -" + DoubleToString(realRisk, 2) + " " + cur + " (" + DoubleToString(InpRiskPct, 1) + " % du compte)\n";
      msg += "Take Profit touché : +" + DoubleToString(realRisk * InpRR, 2) + " " + cur + " (" + DoubleToString(InpRR, 1) + " fois le risque)\n\n";
     }
   else
      msg += "⛔ NE PRENDS PAS CE TRADE : même le lot minimum risquerait plus de " +
             DoubleToString(InpRiskPct, 1) + " % de ton compte.\n\n";

   msg += "📍 LES PRIX\n";
   msg += "Entrée : " + Px(sym, entry) + " (prix actuel)\n";
   msg += "Stop Loss : " + Px(sym, sl) + " (" + Pips(sym, dist) + (buy ? " plus bas" : " plus haut") + ")\n";
   msg += "Take Profit : " + Px(sym, tp) + " (" + Pips(sym, dist * InpRR) + (buy ? " plus haut" : " plus bas") + ")\n\n";
   msg += "❓ POURQUOI\n- " + reason + "\n\n";
   msg += "⚠️ " + (buy ? "N'achète pas si le prix est déjà au-dessus de " : "Ne vends pas si le prix est déjà en dessous de ") +
          Px(sym, limit) + " : le signal est passé.\n";
   msg += "Ne déplace jamais ton Stop Loss.";
   if(newsNear)
      msg += "\nAttention annonce : " + news;

   string sid = sym + "-" + IntegerToString((long)iTime(sym, InpTimeframe, 0));
   if(InpTrack)
      msg += "\nJe te préviens quand le TP ou le SL est touché.";

   //--- données pour l'appli (pas de virgule dans les valeurs)
   string rs = reason;
   StringReplace(rs, "\n- ", " · ");
   StringReplace(rs, ",", ";");
   string tags = "sid=" + sid + ",exp=" + IntegerToString(InpExpireBars) + ",sym=" + sym + ",side=" + (buy ? "buy" : "sell") + ",tf=" + tf +
                 ",entry=" + DoubleToString(entry, dg) + ",sl=" + DoubleToString(sl, dg) +
                 ",tp=" + DoubleToString(tp, dg) + ",lim=" + DoubleToString(limit, dg) +
                 ",slp=" + DoubleToString(dist / PipSize(sym), 1) +
                 ",tpp=" + DoubleToString(dist * InpRR / PipSize(sym), 1) +
                 ",lot=" + DoubleToString(lots, VolDigits(sym)) + ",risk=" + DoubleToString(realRisk, 2) +
                 ",cur=" + cur + ",rr=" + DoubleToString(InpRR, 1) +
                 ",vu=" + IntegerToString((long)(TimeGMT() + validMin * 60)) + ",rs=" + rs;
   Notify(msg, "signal", tags);
   AddTrack(sid, sym, buy, entry, sl, tp);
   return true;
  }

//+------------------------------------------------------------------+
//| Conditions d'un signal sur la bougie "shift"                     |
//| (1 = dernière bougie clôturée, 0 = bougie en cours de formation) |
//+------------------------------------------------------------------+
bool EvalSignal(SymState &st, const int shift, bool &buy, string &reason, double &atr)
  {
   if(!InpSignals)
      return false;
   double close = iClose(st.name, InpTimeframe, shift);
   double rsi = 0, rsiPrev = 0, fast = 0, fastPrev = 0, slow = 0, slowPrev = 0, trend = 0;
   bool hasRsi = TwoValuesAt(st.hRsi, shift, rsi, rsiPrev);
   bool hasMa  = TwoValuesAt(st.hFast, shift, fast, fastPrev) && TwoValuesAt(st.hSlow, shift, slow, slowPrev);
   if(!LastValue(st.hTrend, shift, trend) || !LastValue(st.hAtr, shift, atr) || atr <= 0 || close <= 0)
      return false;

   bool crossUp   = hasMa && fastPrev <= slowPrev && fast > slow;
   bool crossDn   = hasMa && fastPrev >= slowPrev && fast < slow;
   bool upTrend   = close > trend;
   bool downTrend = close < trend;
   string mm  = "MM" + IntegerToString(InpMaFast) + " / MM" + IntegerToString(InpMaSlow);
   string ema = "EMA " + IntegerToString(InpTrendPeriod);

   //--- confirmation sur l'unité de temps supérieure (bougie terminée)
   string extra = "";
   if(InpHtfFilter)
     {
      double htfEma = 0;
      double htfClose = iClose(st.name, InpHtf, 1);
      if(!LastValue(st.hHtf, 1, htfEma) || htfClose <= 0)
         return false; // données pas encore prêtes
      bool htfUp = htfClose > htfEma;
      upTrend   = upTrend && htfUp;
      downTrend = downTrend && !htfUp;
      extra += "\n- Tendance " + (htfUp ? "haussière" : "baissière") + " confirmée en " + TfName(InpHtf);
     }

   //--- force de la tendance
   if(InpAdxMin > 0)
     {
      double adx = 0;
      if(!LastValue(st.hAdx, shift, adx) || adx < InpAdxMin)
         return false;
      extra += "\n- Tendance forte (ADX " + DoubleToString(adx, 0) + ")";
     }

   if(InpSigCross && crossUp && upTrend && (!hasRsi || rsi < InpRsiHigh))
     {
      buy = true;
      reason = mm + " : croisement à la hausse\n- Prix au-dessus de l'" + ema + " (tendance haussière)" + extra;
      return true;
     }
   if(InpSigCross && crossDn && downTrend && (!hasRsi || rsi > InpRsiLow))
     {
      buy = false;
      reason = mm + " : croisement à la baisse\n- Prix sous l'" + ema + " (tendance baissière)" + extra;
      return true;
     }
   if(InpSigPullback && hasRsi && upTrend && rsiPrev <= InpRsiLow && rsi > InpRsiLow)
     {
      buy = true;
      reason = "RSI qui remonte de la survente (" + DoubleToString(rsi, 0) + ") : fin du repli\n- Prix au-dessus de l'" + ema + " (tendance haussière)" + extra;
      return true;
     }
   if(InpSigPullback && hasRsi && downTrend && rsiPrev >= InpRsiHigh && rsi < InpRsiHigh)
     {
      buy = false;
      reason = "RSI qui redescend du surachat (" + DoubleToString(rsi, 0) + ") : fin du rebond\n- Prix sous l'" + ema + " (tendance baissière)" + extra;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Pré-alerte : prévient juste avant la clôture si un signal se     |
//| prépare, pour avoir le temps d'ouvrir MT5                        |
//+------------------------------------------------------------------+
string SecondsText(const int sec)
  {
   if(sec >= 90)
      return IntegerToString((sec + 30) / 60) + " min";
   if(sec >= 50)
      return "1 min";
   return IntegerToString(sec) + " s";
  }

void CheckPreAlert(SymState &st)
  {
   if(!InpPreAlert || !InpSignals || st.lastBar == 0 || MQLInfoInteger(MQL_TESTER))
      return;
   datetime bar = iTime(st.name, InpTimeframe, 0);
   if(bar == 0 || bar == st.preBar)
      return;
   int left = (int)(bar + PeriodSeconds(InpTimeframe) - TimeTradeServer());
   if(left > InpPreAlertSec || left < 5)
      return;
   if(InpOnePerSymbol && InpTrack && HasOpenTrack(st.name))
      return;
   bool buy = false;
   string reason = "";
   double atr = 0;
   if(!EvalSignal(st, 0, buy, reason, atr))
      return;
   string news;
   if(InpNewsBlock && NewsNear(st.name, InpNewsWindow, news))
      return;

   st.preBar = bar;
   datetime closeAt = TimeLocal() + left;
   string side = buy ? "ACHAT" : "VENTE";
   string msg = "⏳ PRÉPARE-TOI : " + side + " " + st.name + " possible à " + TimeToString(closeAt, TIME_MINUTES) +
                " (dans " + SecondsText(left) + ")\n" +
                "Ouvre MT5 sur " + st.name + " maintenant.\n" +
                "Je confirme à la clôture de la bougie avec l'entrée, le Stop Loss, le Take Profit et le lot.\n" +
                "N'entre pas avant la confirmation : le signal peut encore s'annuler.";
   Notify(msg, "pre", "sym=" + st.name + ",side=" + (buy ? "buy" : "sell") + ",ev=pre,at=" +
          IntegerToString((long)(TimeGMT() + left)) + ",tf=" + TfName(InpTimeframe));
  }

//+------------------------------------------------------------------+
//| Analyse d'un symbole à chaque nouvelle bougie                    |
//+------------------------------------------------------------------+
void CheckSymbol(SymState &st)
  {
   datetime bar = iTime(st.name, InpTimeframe, 0);
   if(bar == 0 || bar == st.lastBar)
      return;
   bool first = (st.lastBar == 0);
   st.lastBar = bar;

   string tf    = TfName(InpTimeframe);
   double close = iClose(st.name, InpTimeframe, 1);

   double rsi = 0, rsiPrev = 0;
   bool hasRsi = TwoValues(st.hRsi, rsi, rsiPrev);
   if(hasRsi)
      st.lastRsi = rsi;

   double fast = 0, fastPrev = 0, slow = 0, slowPrev = 0;
   bool hasMa = TwoValues(st.hFast, fast, fastPrev) && TwoValues(st.hSlow, slow, slowPrev);
   bool crossUp = hasMa && fastPrev <= slowPrev && fast > slow;
   bool crossDn = hasMa && fastPrev >= slowPrev && fast < slow;

   if(first)
      return; // première lecture : on mémorise sans alerter

   //--- signal complet sur la bougie qui vient de se clôturer
   bool sent = false;
   bool sigBuy = false;
   string sigReason = "";
   double sigAtr = 0;
   if(EvalSignal(st, 1, sigBuy, sigReason, sigAtr))
      sent = SendSignal(st.name, sigBuy, sigReason, sigAtr);

   //--- une pré-alerte était partie pour cette bougie mais pas de signal : on annule
   if(st.preBar != 0)
     {
      if(st.preBar == iTime(st.name, InpTimeframe, 1) && !sent)
         Notify("✖ PRÉ-ALERTE ANNULÉE : " + st.name + "\nÀ la clôture de la bougie, les conditions ne sont plus réunies. Ne fais rien.",
                "pre", "sym=" + st.name + ",ev=cancel");
      st.preBar = 0;
     }

   //--- alertes simples
   if(InpRsiAlerts && hasRsi)
     {
      if(rsiPrev < InpRsiHigh && rsi >= InpRsiHigh && CooldownOk(st.name + "rsiH", InpCooldownSec))
         Notify(st.name + " " + tf + " : RSI en surachat (" + DoubleToString(rsi, 1) + ")", "market", "sym=" + st.name);
      if(rsiPrev > InpRsiLow && rsi <= InpRsiLow && CooldownOk(st.name + "rsiL", InpCooldownSec))
         Notify(st.name + " " + tf + " : RSI en survente (" + DoubleToString(rsi, 1) + ")", "market", "sym=" + st.name);
     }
   if(InpMaAlerts)
     {
      string mm = "MM" + IntegerToString(InpMaFast) + "/MM" + IntegerToString(InpMaSlow);
      if(crossUp && CooldownOk(st.name + "maUp", InpCooldownSec))
         Notify(st.name + " " + tf + " : croisement haussier " + mm + " à " + Px(st.name, close), "market", "sym=" + st.name);
      if(crossDn && CooldownOk(st.name + "maDn", InpCooldownSec))
         Notify(st.name + " " + tf + " : croisement baissier " + mm + " à " + Px(st.name, close), "market", "sym=" + st.name);
     }
  }

//+------------------------------------------------------------------+
//| Résumé du marché                                                 |
//+------------------------------------------------------------------+
void SendSummary()
  {
   string msg = "RÉSUMÉ DU MARCHÉ " + TfName(InpTimeframe) + "\n";
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      string sym = g_syms[i].name;
      double trend = 0, atr = 0, rsi = 0;
      double close = iClose(sym, InpTimeframe, 1);
      msg += sym + " : ";
      if(LastValue(g_syms[i].hTrend, 1, trend) && close > 0)
         msg += (close > trend ? "hausse" : "baisse");
      if(LastValue(g_syms[i].hRsi, 1, rsi))
         msg += ", RSI " + DoubleToString(rsi, 0);
      if(LastValue(g_syms[i].hAtr, 1, atr))
         msg += ", ATR " + Pips(sym, atr);
      msg += "\n";
     }

   //--- annonces fortes des prochaines 24 h
   if(!MQLInfoInteger(MQL_TESTER))
     {
      datetime now = TimeTradeServer();
      string done = ",", list = "";
      int count = 0;
      for(int s = 0; s < ArraySize(g_syms); s++)
        {
         string cur[];
         int nc = SymbolCurrencies(g_syms[s].name, cur);
      for(int c = 0; c < nc; c++)
           {
            if(StringFind(done, "," + cur[c] + ",") >= 0)
               continue;
            done += cur[c] + ",";
            MqlCalendarValue vals[];
            if(CalendarValueHistory(vals, now, now + 86400, NULL, cur[c]) <= 0)
               continue;
            for(int k = 0; k < ArraySize(vals); k++)
              {
               MqlCalendarEvent ev;
               if(!CalendarEventById(vals[k].event_id, ev) || ev.importance != CALENDAR_IMPORTANCE_HIGH)
                  continue;
               count++;
               if(count <= 5)
                  list += "- " + cur[c] + " " + ev.name + " (" + MinutesText((long)(vals[k].time - now)) + ")\n";
              }
           }
        }
      if(count == 0)
         msg += "Aucune annonce forte dans les 24 h.";
      else
         msg += "Annonces fortes (24 h) : " + IntegerToString(count) + "\n" + list;
     }
   if(InpTrack)
      msg += "\n" + StatsText();
   Notify(msg, "summary");
  }

void CheckSummary()
  {
   if(!InpSummary)
      return;
   MqlDateTime t;
   TimeToStruct(TimeLocal(), t);
   if(t.day_of_week == 0 || t.day_of_week == 6)
      return;
   if(t.hour != InpSummaryHour || t.day_of_year == g_lastSummaryDay)
      return;
   g_lastSummaryDay = t.day_of_year;
   SendSummary();
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
   string s = "AlertesPro  |  " + TfName(InpTimeframe) +
              "  |  risque " + DoubleToString(InpRiskPct, 1) + " %  |  SL ATRx" +
              DoubleToString(InpAtrMult, 1) + "  |  TP " + DoubleToString(InpRR, 1) + "R\n";
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      s += "  " + g_syms[i].name;
      if(g_syms[i].lastRsi > 0)
         s += "   RSI " + DoubleToString(g_syms[i].lastRsi, 1);
      s += "\n";
     }
   if(InpLineAlerts)
      s += "Lignes actives : " + IntegerToString(CountActiveLines()) + "\n";
   if(InpTrack)
      s += StatsText() + "  Signaux en cours : " + IntegerToString(ArraySize(g_tracks)) + "\n";
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
             Px(_Symbol, level) + " (ligne " + name + ")", "line", "sym=" + _Symbol);

      //--- la ligne passe en gris : elle ne sonnera plus
      ObjectSetString(0, name, OBJPROP_TEXT, DONE_TAG);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
     }
   g_lastBid = bid;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Compte : drawdown, perte du jour, marge, positions sans stop     |
//+------------------------------------------------------------------+
double TodayClosedProfit()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   t.hour = 0;
   t.min  = 0;
   t.sec  = 0;
   datetime dayStart = StructToTime(t);
   if(!HistorySelect(dayStart, TimeCurrent() + 60))
      return 0;
   double sum = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong deal = HistoryDealGetTicket(i);
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;
      sum += HistoryDealGetDouble(deal, DEAL_PROFIT) +
             HistoryDealGetDouble(deal, DEAL_SWAP) +
             HistoryDealGetDouble(deal, DEAL_COMMISSION);
     }
   return sum;
  }

void CheckAccount()
  {
   static datetime lastRun = 0;
   if(TimeLocal() - lastRun < 5)
      return;
   lastRun = TimeLocal();

   int pause = (int)MathMax(1, InpAccountPause) * 60;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(InpMaxDrawdown > 0 && balance > 0)
     {
      double dd = (balance - equity) / balance * 100.0;
      if(dd >= InpMaxDrawdown && CooldownOk("dd", pause))
         Notify("Compte : perte latente de " + DoubleToString(dd, 1) + " % (" +
                Money(equity - balance) + ")", "account");
     }

   if(InpDailyLossPct > 0 && balance > 0)
     {
      double day = TodayClosedProfit() + (equity - balance);
      double startBalance = balance - TodayClosedProfit();
      if(startBalance > 0 && -day / startBalance * 100.0 >= InpDailyLossPct && CooldownOk("dayloss", pause * 4))
         Notify("Compte : perte du jour " + Money(day) + " (" +
                DoubleToString(-day / startBalance * 100.0, 1) + " %). Arrête pour aujourd'hui.", "account");
     }

   if(InpMinMargin > 0 && AccountInfoDouble(ACCOUNT_MARGIN) > 0)
     {
      double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml > 0 && ml <= InpMinMargin && CooldownOk("margin", pause))
         Notify("Compte : niveau de marge bas (" + DoubleToString(ml, 0) + " %)", "account");
     }

   if(InpNoStopAlert)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetDouble(POSITION_SL) != 0)
            continue;
         // laisse 2 minutes pour placer le stop après l'ouverture
         if(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME) < 120)
            continue;
         if(CooldownOk("nosl" + IntegerToString((long)ticket), pause))
            Notify("Position SANS stop loss : " + PositionGetString(POSITION_SYMBOL) + " " +
                   DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + " lot (ticket " +
                   IntegerToString((long)ticket) + "). Place un stop.", "account", "sym=" + PositionGetString(POSITION_SYMBOL));
        }
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
             sym + " " + lots + " à " + Px(sym, price), "trade",
             "sym=" + sym + ",side=" + (type == DEAL_TYPE_BUY ? "buy" : "sell") + ",ev=open");
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
          "  Résultat " + Money(profit), "trade",
          "sym=" + sym + ",ev=close,why=" + why + ",profit=" + DoubleToString(profit, 2));
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
   if(InpAtrMult <= 0 || InpRR <= 0 || InpRiskPct <= 0)
     {
      Print("Stop (ATR), ratio gain/risque et risque doivent être positifs.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskPct > 2.0)
      Print("Attention : risquer plus de 2 % par trade vide vite un compte en cas de série perdante.");

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
         Print("Symbole introuvable chez ton courtier : ", sym, " (vérifie le nom exact dans le Market Watch)");
         continue;
        }
      int k = ArraySize(g_syms);
      ArrayResize(g_syms, k + 1);
      g_syms[k].name    = sym;
      g_syms[k].lastBar = 0;
      g_syms[k].lastRsi = 0;
      g_syms[k].preBar  = 0;
      g_syms[k].hFast   = iMA(sym, InpTimeframe, InpMaFast, 0, InpMaMethod, PRICE_CLOSE);
      g_syms[k].hSlow   = iMA(sym, InpTimeframe, InpMaSlow, 0, InpMaMethod, PRICE_CLOSE);
      g_syms[k].hRsi    = iRSI(sym, InpTimeframe, InpRsiPeriod, PRICE_CLOSE);
      g_syms[k].hTrend  = iMA(sym, InpTimeframe, InpTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_syms[k].hAtr    = iATR(sym, InpTimeframe, InpAtrPeriod);
      g_syms[k].hHtf    = InpHtfFilter ? iMA(sym, InpHtf, InpTrendPeriod, 0, MODE_EMA, PRICE_CLOSE) : INVALID_HANDLE;
      g_syms[k].hAdx    = InpAdxMin > 0 ? iADX(sym, InpTimeframe, 14) : INVALID_HANDLE;
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

   //--- reprend les signaux en cours (journal sauvegardé)
   g_statN = 0; g_statWins = 0; g_statR = 0; g_statGrossW = 0; g_statGrossL = 0;
   if(InpTrack)
      LoadJournal();

   //--- Telegram : reprend ou cherche le chat id
   if(InpTelegram && !MQLInfoInteger(MQL_TESTER))
     {
      g_tgChat = "";
      TgLoadChat();
      if(TgChat() == "")
         TgFindChat();
     }

   if(InpTestAtStart && !MQLInfoInteger(MQL_TESTER))
      Notify("AlertesPro démarré : " + IntegerToString(ArraySize(g_syms)) + " marché(s), " +
             TfName(InpTimeframe) + ", risque " + DoubleToString(InpRiskPct, 1) +
             " % par trade. Les alertes arriveront ici." +
             (InpTrack ? "\n" + StatsText() + " En cours : " + IntegerToString(ArraySize(g_tracks)) + "." : ""));

   //--- rattrape les signaux conclus pendant que MT5 était fermé
   if(InpTrack)
      CatchUpTracks();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      if(g_syms[i].hFast  != INVALID_HANDLE) IndicatorRelease(g_syms[i].hFast);
      if(g_syms[i].hSlow  != INVALID_HANDLE) IndicatorRelease(g_syms[i].hSlow);
      if(g_syms[i].hRsi   != INVALID_HANDLE) IndicatorRelease(g_syms[i].hRsi);
      if(g_syms[i].hTrend != INVALID_HANDLE) IndicatorRelease(g_syms[i].hTrend);
      if(g_syms[i].hAtr   != INVALID_HANDLE) IndicatorRelease(g_syms[i].hAtr);
      if(g_syms[i].hHtf   != INVALID_HANDLE) IndicatorRelease(g_syms[i].hHtf);
      if(g_syms[i].hAdx   != INVALID_HANDLE) IndicatorRelease(g_syms[i].hAdx);
     }
   //--- dans le testeur de stratégie : bilan des signaux de la période testée
   if(MQLInfoInteger(MQL_TESTER) && InpTrack)
     {
      string pf = g_statGrossL > 0 ? DoubleToString(g_statGrossW / g_statGrossL, 2) : "n/d";
      Print("===== BILAN ALERTESPRO =====");
      Print(StatsText());
      Print("Facteur de profit : ", pf, "  |  signaux encore ouverts : ", ArraySize(g_tracks));
      Print("Avec ", DoubleToString(InpRiskPct, 1), " % de risque par trade, cela fait environ ",
            DoubleToString(g_statR * InpRiskPct, 1), " % du compte (sans intérêts composés).");
     }
   Comment("");
  }

//+------------------------------------------------------------------+
//| Boucles                                                          |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckLines();
   //--- dans le testeur de stratégie, le minuteur est remplacé par les ticks
   if(MQLInfoInteger(MQL_TESTER))
     {
      for(int i = 0; i < ArraySize(g_syms); i++)
         CheckSymbol(g_syms[i]);
      if(InpTrack)
         CheckTracks();
     }
  }

void OnTimer()
  {
   CheckLines();
   if(InpTrack)
      CheckTracks();
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      CheckSymbol(g_syms[i]);
      CheckPreAlert(g_syms[i]);
     }
   CheckAccount();
   CheckNews();
   CheckSummary();
   CheckStatus();
   CheckTelegram();
   UpdatePanel();
  }

//--- met à jour le panneau quand on ajoute ou supprime une ligne
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DELETE || id == CHARTEVENT_OBJECT_DRAG)
      UpdatePanel();
  }
//+------------------------------------------------------------------+
