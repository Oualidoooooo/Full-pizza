//+------------------------------------------------------------------+
//|                                                  AlertesPro.mq5  |
//|  Robot d'alertes de trading pour MetaTrader 5                     |
//|  - Signaux complets : entrée, stop loss, take profit, lot        |
//|    (filtre de tendance EMA 200, stop basé sur l'ATR)             |
//|  - Calendrier économique : prévient avant les annonces fortes    |
//|  - Résumé du marché chaque matin                                 |
//|  - Lignes de prix, croisement MM, RSI                            |
//|  - Ouverture / fermeture de positions, drawdown, marge           |
//|  Canaux : fenêtre MT5, son, push mobile MT5, e-mail, Telegram    |
//|  Le robot ne passe AUCUN ordre : il surveille et il prévient.    |
//+------------------------------------------------------------------+
#property copyright "AlertesPro"
#property version   "1.10"
#property description "Signaux avec stop loss / take profit / lot, calendrier économique, résumé du matin."
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
input string InpTgChatId     = "";            // Telegram : chat id
input bool   InpTestAtStart  = true;          // Envoyer un message de test au démarrage

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
   datetime          lastBar;
   double            lastRsi;
  };

SymState g_syms[];
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

bool TwoValues(const int handle, double &cur, double &prev)
  {
   if(handle == INVALID_HANDLE)
      return false;
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(handle, 0, 1, 2, b) != 2)
      return false;
   cur  = b[0]; // dernière bougie clôturée
   prev = b[1]; // celle d'avant
   return true;
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
                   cur[c] + ".");
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
//| Construction d'un signal complet                                 |
//+------------------------------------------------------------------+
void SendSignal(const string sym, const bool buy, const string reason, const double atr)
  {
   string tf = TfName(InpTimeframe);
   if(!CooldownOk(sym + (buy ? "sigB" : "sigS"), (int)MathMax(InpCooldownSec, PeriodSeconds(InpTimeframe))))
      return;

   //--- spread trop large par rapport à la volatilité
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(ask <= 0 || bid <= 0)
      return;
   if(InpMaxSpreadAtr > 0 && (ask - bid) > atr * InpMaxSpreadAtr)
     {
      Print(sym, " : signal ignoré, spread trop large (", Pips(sym, ask - bid), ").");
      return;
     }

   //--- annonce économique proche
   string news;
   bool newsNear = NewsNear(sym, InpNewsWindow, news);
   if(newsNear && InpNewsBlock)
     {
      Print(sym, " : signal ignoré à cause de l'annonce ", news);
      return;
     }

   double entry = buy ? ask : bid;
   double dist  = atr * InpAtrMult;
   double sl    = buy ? entry - dist : entry + dist;
   double tp    = buy ? entry + dist * InpRR : entry - dist * InpRR;

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPct / 100.0;
   double realRisk  = 0;
   double lots      = LotForRisk(sym, dist, riskMoney, realRisk);

   string msg = "SIGNAL " + (buy ? "ACHAT " : "VENTE ") + sym + " " + tf + "\n" +
                reason + "\n" +
                "Entrée " + Px(sym, entry) + "\n" +
                "SL " + Px(sym, sl) + " (" + Pips(sym, dist) + ")\n" +
                "TP " + Px(sym, tp) + " (" + Pips(sym, dist * InpRR) + ")\n";
   if(lots > 0)
      msg += "Lot " + DoubleToString(lots, VolDigits(sym)) + " = risque " +
             DoubleToString(realRisk, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) +
             " (" + DoubleToString(InpRiskPct, 1) + " %)";
   else
      msg += "Lot minimum trop gros pour " + DoubleToString(InpRiskPct, 1) + " % de risque : passe ton tour.";
   if(newsNear)
      msg += "\nAttention annonce : " + news;

   Notify(msg);
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

   double trend = 0, atr = 0;
   bool hasTrend = LastValue(st.hTrend, 1, trend);
   bool hasAtr   = LastValue(st.hAtr, 1, atr);

   if(first)
      return; // première lecture : on mémorise sans alerter

   //--- signaux complets
   if(InpSignals && hasTrend && hasAtr && atr > 0 && close > 0)
     {
      bool upTrend   = close > trend;
      bool downTrend = close < trend;
      string mm = "MM" + IntegerToString(InpMaFast) + "/MM" + IntegerToString(InpMaSlow);
      string ema = "EMA" + IntegerToString(InpTrendPeriod);

      if(InpSigCross && crossUp && upTrend && (!hasRsi || rsi < InpRsiHigh))
         SendSignal(st.name, true, "Croisement haussier " + mm + ", prix au-dessus de l'" + ema, atr);
      else if(InpSigCross && crossDn && downTrend && (!hasRsi || rsi > InpRsiLow))
         SendSignal(st.name, false, "Croisement baissier " + mm + ", prix sous l'" + ema, atr);
      else if(InpSigPullback && hasRsi && upTrend && rsiPrev <= InpRsiLow && rsi > InpRsiLow)
         SendSignal(st.name, true, "Rebond du RSI depuis la survente, tendance haussière (" + ema + ")", atr);
      else if(InpSigPullback && hasRsi && downTrend && rsiPrev >= InpRsiHigh && rsi < InpRsiHigh)
         SendSignal(st.name, false, "Repli du RSI depuis le surachat, tendance baissière (" + ema + ")", atr);
     }

   //--- alertes simples
   if(InpRsiAlerts && hasRsi)
     {
      if(rsiPrev < InpRsiHigh && rsi >= InpRsiHigh && CooldownOk(st.name + "rsiH", InpCooldownSec))
         Notify(st.name + " " + tf + " : RSI en surachat (" + DoubleToString(rsi, 1) + ")");
      if(rsiPrev > InpRsiLow && rsi <= InpRsiLow && CooldownOk(st.name + "rsiL", InpCooldownSec))
         Notify(st.name + " " + tf + " : RSI en survente (" + DoubleToString(rsi, 1) + ")");
     }
   if(InpMaAlerts)
     {
      string mm = "MM" + IntegerToString(InpMaFast) + "/MM" + IntegerToString(InpMaSlow);
      if(crossUp && CooldownOk(st.name + "maUp", InpCooldownSec))
         Notify(st.name + " " + tf + " : croisement haussier " + mm + " à " + Px(st.name, close));
      if(crossDn && CooldownOk(st.name + "maDn", InpCooldownSec))
         Notify(st.name + " " + tf + " : croisement baissier " + mm + " à " + Px(st.name, close));
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
   Notify(msg);
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
                Money(equity - balance) + ")");
     }

   if(InpDailyLossPct > 0 && balance > 0)
     {
      double day = TodayClosedProfit() + (equity - balance);
      double startBalance = balance - TodayClosedProfit();
      if(startBalance > 0 && -day / startBalance * 100.0 >= InpDailyLossPct && CooldownOk("dayloss", pause * 4))
         Notify("Compte : perte du jour " + Money(day) + " (" +
                DoubleToString(-day / startBalance * 100.0, 1) + " %). Arrête pour aujourd'hui.");
     }

   if(InpMinMargin > 0 && AccountInfoDouble(ACCOUNT_MARGIN) > 0)
     {
      double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml > 0 && ml <= InpMinMargin && CooldownOk("margin", pause))
         Notify("Compte : niveau de marge bas (" + DoubleToString(ml, 0) + " %)");
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
                   IntegerToString((long)ticket) + "). Place un stop.");
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
      g_syms[k].hFast   = iMA(sym, InpTimeframe, InpMaFast, 0, InpMaMethod, PRICE_CLOSE);
      g_syms[k].hSlow   = iMA(sym, InpTimeframe, InpMaSlow, 0, InpMaMethod, PRICE_CLOSE);
      g_syms[k].hRsi    = iRSI(sym, InpTimeframe, InpRsiPeriod, PRICE_CLOSE);
      g_syms[k].hTrend  = iMA(sym, InpTimeframe, InpTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_syms[k].hAtr    = iATR(sym, InpTimeframe, InpAtrPeriod);
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
      Notify("AlertesPro démarré : " + IntegerToString(ArraySize(g_syms)) + " marché(s), " +
             TfName(InpTimeframe) + ", risque " + DoubleToString(InpRiskPct, 1) +
             " % par trade. Les alertes arriveront ici.");
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
      for(int i = 0; i < ArraySize(g_syms); i++)
         CheckSymbol(g_syms[i]);
  }

void OnTimer()
  {
   CheckLines();
   for(int i = 0; i < ArraySize(g_syms); i++)
      CheckSymbol(g_syms[i]);
   CheckAccount();
   CheckNews();
   CheckSummary();
   UpdatePanel();
  }

//--- met à jour le panneau quand on ajoute ou supprime une ligne
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DELETE || id == CHARTEVENT_OBJECT_DRAG)
      UpdatePanel();
  }
//+------------------------------------------------------------------+
