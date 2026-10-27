//+------------------------------------------------------------------+
//|                                              AlertesProAuto.mq5 |
//|  Passe automatiquement les ordres des signaux AlertesPro         |
//|  UNIQUEMENT sur un compte DÉMO.                                  |
//|                                                                  |
//|  - récupère TES signaux sur le serveur AlertesPro (volume        |
//|    calculé pour ton capital et ta perte max)                     |
//|  - ouvre l'ordre avec Stop Loss et TP2                           |
//|  - à TP1 : ferme la moitié et met le Stop Loss au prix d'entrée  |
//+------------------------------------------------------------------+
#property copyright "AlertesPro"
#property version   "1.00"
#property description "Passe tout seul les ordres des signaux AlertesPro, seulement sur un compte DÉMO."
#property description "À TP1 : ferme la moitié et met le Stop Loss au prix d'entrée."

#include <Trade/Trade.mqh>

input string InpServerUrl = "https://omk81.moukramm.workers.dev"; // Adresse du serveur AlertesPro
input string InpEmail     = "";      // Ton e-mail AlertesPro (celui de l'appli)
input string InpPassword  = "";      // Ton mot de passe AlertesPro
input bool   InpHalfAtTp1 = true;    // À TP1 : fermer la moitié et protéger le reste
input int    InpSlippage  = 30;      // Glissement de prix accepté (en points)

const long   MAGIC      = 20261027;
const string TOKEN_FILE = "AlertesProAuto_jeton.txt";
const string STATE_FILE = "AlertesProAuto_etat.txt";

CTrade   trade;
string   g_token    = "";
string   g_done     = ",";      // signaux déjà traités (",id,id,")
datetime g_lastPoll = 0;
datetime g_lastLogin = 0;
string   g_info     = "Démarrage...";
int      g_nbOrders = 0;

//--- trades suivis pour la sortie à TP1
struct Pos
  {
   string            id;
   ulong             ticket;
   double            tp1;
   double            half;
   int               state;   // 0 = en attente de TP1, 1 = TP1 fait
  };
Pos g_pos[];

//+------------------------------------------------------------------+
//| Fichiers                                                         |
//+------------------------------------------------------------------+
string ReadText(const string file)
  {
   if(!FileIsExist(file))
      return "";
   int h = FileOpen(file, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return "";
   string s = "";
   while(!FileIsEnding(h))
      s += FileReadString(h) + "\n";
   FileClose(h);
   return s;
  }

void WriteText(const string file, const string text)
  {
   int h = FileOpen(file, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileWriteString(h, text);
   FileClose(h);
  }

void SaveState()
  {
   string s = "DONE;" + g_done + "\n";
   for(int i = 0; i < ArraySize(g_pos); i++)
      s += "POS;" + g_pos[i].id + ";" + IntegerToString((long)g_pos[i].ticket) + ";" +
           DoubleToString(g_pos[i].tp1, 8) + ";" + DoubleToString(g_pos[i].half, 2) + ";" + IntegerToString(g_pos[i].state) + "\n";
   WriteText(STATE_FILE, s);
  }

void LoadState()
  {
   ArrayResize(g_pos, 0);
   string lines[];
   int n = StringSplit(ReadText(STATE_FILE), '\n', lines);
   for(int i = 0; i < n; i++)
     {
      string f[];
      int k = StringSplit(lines[i], ';', f);
      if(k >= 2 && f[0] == "DONE")
         g_done = f[1];
      else if(k >= 6 && f[0] == "POS")
        {
         int j = ArraySize(g_pos);
         ArrayResize(g_pos, j + 1);
         g_pos[j].id     = f[1];
         g_pos[j].ticket = (ulong)StringToInteger(f[2]);
         g_pos[j].tp1    = StringToDouble(f[3]);
         g_pos[j].half   = StringToDouble(f[4]);
         g_pos[j].state  = (int)StringToInteger(f[5]);
        }
     }
   if(StringLen(g_done) > 3000) // garde seulement les derniers
      g_done = "," + StringSubstr(g_done, StringLen(g_done) - 2000);
  }

//+------------------------------------------------------------------+
//| Serveur                                                          |
//+------------------------------------------------------------------+
string ServerBase()
  {
   string u = InpServerUrl;
   StringTrimLeft(u);
   StringTrimRight(u);
   while(StringLen(u) > 0 && StringGetCharacter(u, StringLen(u) - 1) == '/')
      u = StringSubstr(u, 0, StringLen(u) - 1);
   return u;
  }

string JsonEsc(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   return s;
  }

//--- renvoie le code HTTP (-1 si pas de connexion) et le texte reçu
int Http(const string method, const string path, const string body, string &answer)
  {
   static bool told = false;
   char post[], result[];
   string resHeaders;
   string headers = "Content-Type: application/json\r\n";
   if(g_token != "")
      headers += "Authorization: Bearer " + g_token + "\r\n";
   if(body != "")
     {
      int len = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);
      if(len > 0)
         ArrayResize(post, len - 1);
     }
   ResetLastError();
   int code = WebRequest(method, ServerBase() + path, headers, 8000, post, result, resHeaders);
   if(code == -1)
     {
      if(GetLastError() == 4014 && !told)
        {
         Alert("AlertesPro Auto : ajoute ", ServerBase(), " dans Outils > Options > Expert Advisors > WebRequest.");
         told = true;
        }
      g_info = "Pas de connexion au serveur";
      return -1;
     }
   answer = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   return code;
  }

bool Login()
  {
   if(InpEmail == "" || InpPassword == "")
     {
      g_info = "Remplis ton e-mail et ton mot de passe AlertesPro dans les paramètres";
      return false;
     }
   if(TimeLocal() - g_lastLogin < 60)
      return false;
   g_lastLogin = TimeLocal();
   g_token = "";
   string ans;
   int code = Http("POST", "/api/login", "{\"email\":\"" + JsonEsc(InpEmail) + "\",\"password\":\"" + JsonEsc(InpPassword) + "\"}", ans);
   if(code != 200)
     {
      g_info = (code == 401) ? "E-mail ou mot de passe AlertesPro incorrect" : "Connexion au compte impossible (" + IntegerToString(code) + ")";
      Print("AlertesPro Auto : ", g_info);
      return false;
     }
   int p = StringFind(ans, "\"token\":\"");
   if(p < 0)
      return false;
   p += 9;
   int q = StringFind(ans, "\"", p);
   g_token = StringSubstr(ans, p, q - p);
   WriteText(TOKEN_FILE, g_token);
   Print("AlertesPro Auto : connecté au compte ", InpEmail);
   return true;
  }

//+------------------------------------------------------------------+
//| Symbole du courtier (EURUSD, EURUSD.m, EURUSDm, GOLD...)          |
//+------------------------------------------------------------------+
string FindSymbol(const string name)
  {
   if(SymbolInfoInteger(name, SYMBOL_EXIST) && SymbolSelect(name, true))
      return name;
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
     {
      string s = SymbolName(i, false);
      if(StringFind(s, name) == 0 && StringLen(s) <= StringLen(name) + 4 && SymbolSelect(s, true))
         return s;
     }
   if(name == "XAUUSD")
      return FindSymbol("GOLD");
   return "";
  }

double NormLot(const string sym, double lot)
  {
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0)
      step = 0.01;
   lot = MathFloor(lot / step + 1e-9) * step;
   if(lot > vmax)
      lot = vmax;
   if(lot < vmin)
      return 0;
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
//| Passer l'ordre d'un signal                                       |
//| S|id|sym|side|entry|sl|tp1|tp|r1|r2|lot|vu|lim|tf                |
//+------------------------------------------------------------------+
void Execute(string &f[])
  {
   string id   = f[1];
   string name = f[2];
   bool   buy  = (f[3] == "buy");
   double entry = StringToDouble(f[4]), sl0 = StringToDouble(f[5]), tp10 = StringToDouble(f[6]), tp0 = StringToDouble(f[7]);
   double r1 = StringToDouble(f[8]);
   double lot = StringToDouble(f[10]);
   long   vu  = StringToInteger(f[11]);
   g_done += id + ",";
   SaveState();

   if((long)TimeGMT() > vu)
     {
      Print("AlertesPro Auto : signal ", name, " trop vieux, ignoré.");
      return;
     }
   string sym = FindSymbol(name);
   if(sym == "")
     {
      Print("AlertesPro Auto : ", name, " introuvable chez ton courtier, signal ignoré.");
      return;
     }
   int    dg   = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double ask  = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double px   = buy ? ask : bid;
   double dist = MathAbs(entry - sl0);
   if(px <= 0 || dist <= 0)
      return;

   //--- trop tard ? (le prix est déjà parti trop loin dans le bon sens)
   double moved = buy ? px - entry : entry - px;
   if(MathAbs(px - entry) < 2 * dist && moved > 0.5 * dist)
     {
      Print("AlertesPro Auto : ", sym, " trop tard, le prix est déjà parti (", DoubleToString(px, dg), ").");
      return;
     }

   //--- mêmes distances que le signal, à partir du vrai prix du courtier
   double k   = buy ? 1.0 : -1.0;
   double r2  = MathAbs(tp0 - entry) / dist;
   double sl  = NormalizeDouble(px - k * dist, dg);
   double tp  = NormalizeDouble(px + k * dist * r2, dg);
   double tp1 = (r1 > 0 && tp10 > 0) ? NormalizeDouble(px + k * dist * r1, dg) : 0;

   double stopLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(sym, SYMBOL_POINT);
   if(dist <= stopLevel)
     {
      Print("AlertesPro Auto : ", sym, " Stop Loss trop proche pour ton courtier, signal ignoré.");
      return;
     }

   double vol = NormLot(sym, lot);
   if(vol <= 0)
     {
      Print("AlertesPro Auto : volume trop petit pour ", sym, ", signal ignoré.");
      return;
     }
   double half = NormLot(sym, vol / 2.0);
   bool split = InpHalfAtTp1 && tp1 > 0 && half > 0 && NormLot(sym, vol - half) > 0;
   if(tp1 > 0 && !split)
      tp = tp1;                       // volume trop petit pour couper : on vise TP1

   //--- assez de marge ?
   double margin = 0;
   if(OrderCalcMargin(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, vol, px, margin) && margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      Print("AlertesPro Auto : pas assez de marge pour ", DoubleToString(vol, 2), " lot de ", sym, ".");
      return;
     }

   trade.SetExpertMagicNumber(MAGIC);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(sym);
   string comment = "AlertesPro " + id;
   bool ok = buy ? trade.Buy(vol, sym, 0.0, sl, tp, comment) : trade.Sell(vol, sym, 0.0, sl, tp, comment);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     {
      Print("AlertesPro Auto : ordre refusé sur ", sym, " (", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription(), ").");
      return;
     }
   g_nbOrders++;
   Print("AlertesPro Auto : ", (buy ? "ACHAT " : "VENTE "), DoubleToString(vol, 2), " lot ", sym, " | SL ", DoubleToString(sl, dg),
         " | TP ", DoubleToString(tp, dg), (split ? " | TP1 " + DoubleToString(tp1, dg) + " (moitié)" : ""));
   if(split)
     {
      int j = ArraySize(g_pos);
      ArrayResize(g_pos, j + 1);
      g_pos[j].id     = id;
      g_pos[j].ticket = trade.ResultOrder();   // identifiant de la position = ticket de l'ordre d'ouverture
      g_pos[j].tp1    = tp1;
      g_pos[j].half   = half;
      g_pos[j].state  = 0;
      SaveState();
     }
  }

//+------------------------------------------------------------------+
//| Trouver la position ouverte par un ordre                          |
//+------------------------------------------------------------------+
bool SelectPos(const ulong ident)
  {
   if(PositionSelectByTicket(ident))
      return true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER) == ident)
         return true;
     }
   return false;
  }

//--- TP1 : ferme la moitié, met le Stop Loss au prix d'entrée
void ManagePositions()
  {
   bool changed = false;
   for(int i = ArraySize(g_pos) - 1; i >= 0; i--)
     {
      if(!SelectPos(g_pos[i].ticket))
        {
         //--- position fermée (Stop Loss ou TP) : on arrête de la suivre
         for(int j = i; j < ArraySize(g_pos) - 1; j++)
            g_pos[j] = g_pos[j + 1];
         ArrayResize(g_pos, ArraySize(g_pos) - 1);
         changed = true;
         continue;
        }
      if(g_pos[i].state != 0)
         continue;
      ulong  ticket = PositionGetInteger(POSITION_TICKET);
      string sym    = PositionGetString(POSITION_SYMBOL);
      bool   buy    = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp     = PositionGetDouble(POSITION_TP);
      double px     = buy ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      if(px <= 0 || (buy ? px < g_pos[i].tp1 : px > g_pos[i].tp1))
         continue;
      trade.SetExpertMagicNumber(MAGIC);
      trade.SetDeviationInPoints(InpSlippage);
      trade.SetTypeFillingBySymbol(sym);
      if(trade.PositionClosePartial(ticket, g_pos[i].half))
         Print("AlertesPro Auto : TP1 touché sur ", sym, ", moitié fermée (", DoubleToString(g_pos[i].half, 2), " lot).");
      if(SelectPos(g_pos[i].ticket))
        {
         ticket = PositionGetInteger(POSITION_TICKET);
         if(trade.PositionModify(ticket, NormalizeDouble(open, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), tp))
            Print("AlertesPro Auto : Stop Loss de ", sym, " mis au prix d'entrée, plus de risque.");
        }
      g_pos[i].state = 1;
      changed = true;
     }
   if(changed)
      SaveState();
  }

//+------------------------------------------------------------------+
//| Récupérer les signaux                                            |
//+------------------------------------------------------------------+
void Poll()
  {
   if(TimeLocal() - g_lastPoll < 10)
      return;
   g_lastPoll = TimeLocal();
   if(g_token == "" && !Login())
      return;
   string ans;
   int code = Http("GET", "/api/ea", "", ans);
   if(code == 401)
     {
      g_token = "";
      Login();
      return;
     }
   if(code != 200)
     {
      if(code > 0)
         g_info = "Serveur : réponse " + IntegerToString(code);
      return;
     }
   g_info = "Connecté · dernier contrôle " + TimeToString(TimeLocal(), TIME_SECONDS);
   string lines[];
   int n = StringSplit(ans, '\n', lines);
   for(int i = 0; i < n; i++)
     {
      string f[];
      if(StringSplit(lines[i], '|', f) < 14 || f[0] != "S")
         continue;
      if(StringFind(g_done, "," + f[1] + ",") >= 0)
         continue;
      Execute(f);
     }
  }

void ShowPanel()
  {
   Comment("AlertesPro Auto (compte DÉMO)\n", g_info, "\nOrdres passés depuis le démarrage : ", g_nbOrders,
           "\nTrades suivis pour TP1 : ", ArraySize(g_pos));
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
     {
      Alert("AlertesPro Auto ne marche que sur un compte DÉMO. Connecte-toi à ton compte démo dans MT5.");
      return INIT_FAILED;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Alert("AlertesPro Auto : active le bouton « Algo Trading » en haut de MT5, sinon aucun ordre ne passera.");
   g_token = ReadText(TOKEN_FILE);
   StringTrimRight(g_token);
   StringTrimLeft(g_token);
   LoadState();
   EventSetTimer(2);
   Poll();
   ShowPanel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

void OnTimer()
  {
   ManagePositions();
   Poll();
   ShowPanel();
  }

void OnTick()
  {
   ManagePositions();
  }
//+------------------------------------------------------------------+
