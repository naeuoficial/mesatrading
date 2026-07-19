//+------------------------------------------------------------------+
//|                                                       MesaEA.mq4 |
//|      MESA - Mesa de Operacoes Algoritmica :: Robo-base MQL4      |
//|                                                                  |
//|  Versao MetaTrader 4 (API classica) do robo-base da plataforma.  |
//|  Funcionalmente equivalente a versao MQL5, porem escrito 100%    |
//|  com a API idiomatica do MQL4: iMA/iRSI/iMACD/iATR/iBands/iADX   |
//|  chamados por shift, OrderSend/OrderSelect/OrderModify/OrderClose|
//|  e MarketInfo. Nao depende de nenhum include externo.            |
//|                                                                  |
//|  SUMARIO DAS SECOES                                              |
//|    S01 - Enumeracoes                                             |
//|    S02 - Parametros de entrada (inputs) agrupados                |
//|    S03 - Variaveis globais e estruturas                          |
//|    S04 - Utilitarios gerais (texto, CSV, arredondamento)         |
//|    S05 - Leitura de indicadores (IndicatorSnapshot)              |
//|    S06 - Motor de sinal ponderado (ComputeScore)                 |
//|    S07 - Filtros de tempo (IsTradingAllowed)                     |
//|    S08 - Estatisticas diarias                                    |
//|    S09 - Gestao de risco e dimensionamento de volume             |
//|    S10 - Execucao de ordens (com retry)                          |
//|    S11 - Gestao de posicoes abertas (BE / trailing / fechamento) |
//|    S12 - Painel on-chart                                         |
//|    S13 - Handlers de evento (OnInit / OnDeinit / OnTick)         |
//+------------------------------------------------------------------+
#property copyright "MESA - Mesa de Operacoes Algoritmica"
#property link      "https://mesa.local"
#property version   "1.00"
#property strict
#property description "Robo-base MESA para MetaTrader 4 - motor de sinal ponderado com filtros de tempo granulares e gestao de risco completa."

//==================================================================//
//  S01 - ENUMERACOES                                               //
//==================================================================//

//--- Modo de dimensionamento do volume
enum ENUM_MODO_VOLUME
  {
   VOLUME_LOTE_FIXO = 0,   // Lote fixo
   VOLUME_RISCO_PCT = 1    // Risco % do saldo (derivado do stop)
  };

//--- Modo de calculo de Stop Loss / Take Profit
enum ENUM_MODO_STOP
  {
   STOP_MULTIPLO_ATR = 0,  // Multiplo do ATR
   STOP_PONTOS_FIXOS = 1   // Pips/pontos fixos
  };

//--- Direcao logica de um sinal
#define SINAL_NEUTRO   0
#define SINAL_COMPRA   1
#define SINAL_VENDA   -1

//==================================================================//
//  S02 - PARAMETROS DE ENTRADA                                     //
//==================================================================//
//  Observacao: o MQL4 nao suporta a diretiva "input group" do MQL5.
//  Por isso os agrupamentos sao feitos com inputs do tipo string
//  usados como separadores visuais na janela de propriedades.
//------------------------------------------------------------------

input string GRUPO_01 = "===== 01. IDENTIFICACAO E EXECUCAO =====";        // 01. Identificacao e Execucao
input int    MagicNumber          = 20260719;  // Numero magico (identifica as ordens do EA)
input string ComentarioOrdem      = "MESA";    // Comentario gravado nas ordens
input int    TimeframeAnalise     = 0;         // Timeframe de analise (0 = grafico atual)
input bool   UsarCandleFechado    = true;      // Ler indicadores no candle fechado (shift 1)
input bool   OperarSomenteNovaBarra = true;    // Avaliar sinal apenas na abertura de nova barra
input int    MaxTentativasEnvio   = 5;         // Tentativas de reenvio em caso de erro
input int    PausaEntreTentativasMs = 300;     // Pausa entre tentativas (ms)
input double DesvioMaximoPips     = 3.0;       // Desvio maximo aceito (slippage, em pips)
input bool   EnviarStopsSeparados = false;     // Enviar ordem sem SL/TP e aplicar via OrderModify (contas ECN)

input string GRUPO_02 = "===== 02. INDICADORES =====";                     // 02. Indicadores
input int    EmaRapidaPeriodo     = 12;        // EMA rapida - periodo
input int    EmaLentaPeriodo      = 34;        // EMA lenta - periodo
input int    EmaPrecoAplicado     = PRICE_CLOSE; // EMA - preco aplicado
input int    RsiPeriodo           = 14;        // RSI - periodo
input int    RsiPrecoAplicado     = PRICE_CLOSE; // RSI - preco aplicado
input int    MacdRapida           = 12;        // MACD - EMA rapida
input int    MacdLenta            = 26;        // MACD - EMA lenta
input int    MacdSinal            = 9;         // MACD - periodo do sinal
input int    AtrPeriodo           = 14;        // ATR - periodo
input int    BollingerPeriodo     = 20;        // Bollinger - periodo
input double BollingerDesvio      = 2.0;       // Bollinger - desvio padrao
input int    AdxPeriodo           = 14;        // ADX - periodo

input string GRUPO_03 = "===== 03. MOTOR DE SINAL - PESOS =====";          // 03. Motor de Sinal - Pesos
input double PesoEma              = 30.0;      // Peso da EMA (tendencia)
input double PesoRsi              = 15.0;      // Peso do RSI (momento/exaustao)
input double PesoMacd             = 25.0;      // Peso do MACD (momento)
input double PesoBollinger        = 10.0;      // Peso das Bandas de Bollinger (posicao)
input double PesoAdx              = 15.0;      // Peso do ADX (forca direcional)
input double PesoAtr              = 5.0;       // Peso do ATR (impulso normalizado)

input string GRUPO_04 = "===== 04. MOTOR DE SINAL - LIMIARES E MODOS ====="; // 04. Motor de Sinal - Limiares e Modos
input double LimiarCompra         = 35.0;      // Score minimo para COMPRA (0..100)
input double LimiarVenda          = 35.0;      // Score minimo (em modulo) para VENDA (0..100)
input bool   PermitirCompras      = true;      // Permitir operacoes de compra
input bool   PermitirVendas       = true;      // Permitir operacoes de venda
input double RsiSobrecompra       = 70.0;      // RSI - nivel de sobrecompra
input double RsiSobrevenda        = 30.0;      // RSI - nivel de sobrevenda
input bool   RsiModoReversao      = false;     // RSI em modo reversao (contra-tendencia)
input bool   BollingerModoReversao= false;     // Bollinger em modo reversao (contra-tendencia)
input double EmaNormalizador      = 1.0;       // Divisor da distancia EMA/ATR (sensibilidade)
input double AdxEscala            = 40.0;      // ADX que representa forca maxima (score 1.0)
input double AdxMinimo            = 0.0;       // ADX minimo para operar (0 = desligado)
input double AtrMinimoPips        = 0.0;       // ATR minimo em pips (0 = desligado)
input double AtrMaximoPips        = 0.0;       // ATR maximo em pips (0 = desligado)

input string GRUPO_05 = "===== 05. FILTRO DE HORARIO =====";               // 05. Filtro de Horario
input bool   UsarFiltroHorario    = true;      // Ativar filtro de janela de horario
input int    HoraInicio           = 9;         // Hora de inicio (0-23)
input int    MinutoInicio         = 0;         // Minuto de inicio (0-59)
input int    HoraFim              = 17;        // Hora de fim (0-23)
input int    MinutoFim            = 30;        // Minuto de fim (0-59)

input string GRUPO_06 = "===== 06. FILTRO DE DIAS DA SEMANA =====";        // 06. Filtro de Dias da Semana
input bool   OperarSegunda        = true;      // Operar as segundas-feiras
input bool   OperarTerca          = true;      // Operar as tercas-feiras
input bool   OperarQuarta         = true;      // Operar as quartas-feiras
input bool   OperarQuinta         = true;      // Operar as quintas-feiras
input bool   OperarSexta          = true;      // Operar as sextas-feiras
input bool   OperarSabado         = false;     // Operar aos sabados
input bool   OperarDomingo        = false;     // Operar aos domingos

input string GRUPO_07 = "===== 07. FILTRO DE DIAS DO MES =====";           // 07. Filtro de Dias do Mes
input bool   UsarFiltroDiaMes     = false;     // Ativar filtro de dias do mes
input string DiasDoMesPermitidos  = "1-31";    // Dias permitidos - CSV com intervalos: "1,2,15-20,31"

input string GRUPO_08 = "===== 08. FILTRO DE MESES =====";                 // 08. Filtro de Meses
input bool   UsarFiltroMes        = false;     // Ativar filtro de meses
input string MesesPermitidos      = "1-12";    // Meses permitidos - CSV com intervalos: "1-6,9,10-12"

input string GRUPO_09 = "===== 09. FILTRO DE ANOS =====";                  // 09. Filtro de Anos
input bool   UsarFiltroAno        = false;     // Ativar filtro de anos
input int    AnoMinimo            = 2000;      // Ano minimo permitido
input int    AnoMaximo            = 2099;      // Ano maximo permitido

input string GRUPO_10 = "===== 10. BLACKOUT DE DATAS =====";               // 10. Blackout de Datas
input bool   UsarBlackoutDatas    = false;     // Ativar bloqueio por datas especificas
input string DatasBloqueadas      = "";        // Datas AAAA.MM.DD - CSV, aceita intervalos "2026.12.24-2026.12.26"

input string GRUPO_11 = "===== 11. FILTRO DE SESSOES =====";               // 11. Filtro de Sessoes
input bool   UsarFiltroSessao     = false;     // Ativar filtro de sessoes de mercado
input double OffsetGmtServidor    = 3.0;       // Offset GMT do servidor (ex.: 3 = GMT+3)
input bool   SessaoAsia           = false;     // Operar na sessao da Asia
input int    AsiaInicioGmt        = 0;         // Asia - hora de inicio (GMT)
input int    AsiaFimGmt           = 9;         // Asia - hora de fim (GMT)
input bool   SessaoLondres        = true;      // Operar na sessao de Londres
input int    LondresInicioGmt     = 7;         // Londres - hora de inicio (GMT)
input int    LondresFimGmt        = 16;        // Londres - hora de fim (GMT)
input bool   SessaoNovaYork       = true;      // Operar na sessao de Nova York
input int    NovaYorkInicioGmt    = 12;        // Nova York - hora de inicio (GMT)
input int    NovaYorkFimGmt       = 21;        // Nova York - hora de fim (GMT)

input string GRUPO_12 = "===== 12. VOLUME E RISCO =====";                  // 12. Volume e Risco
input ENUM_MODO_VOLUME ModoVolume = VOLUME_LOTE_FIXO; // Modo de dimensionamento do volume
input double LoteFixo             = 0.10;      // Lote fixo (quando modo = lote fixo)
input double RiscoPorTradePct     = 1.0;       // Risco por trade em % do saldo
input double LoteMaximoPermitido  = 10.0;      // Teto de lote (protecao)

input string GRUPO_13 = "===== 13. STOP LOSS E TAKE PROFIT =====";         // 13. Stop Loss e Take Profit
input ENUM_MODO_STOP ModoStop     = STOP_MULTIPLO_ATR; // Modo de calculo de SL/TP
input double StopAtrMultiplicador = 2.0;       // SL = ATR x multiplicador
input double TakeAtrMultiplicador = 3.0;       // TP = ATR x multiplicador
input double StopLossPips         = 300.0;     // SL fixo em pips (modo pontos fixos)
input double TakeProfitPips       = 600.0;     // TP fixo em pips (modo pontos fixos)
input bool   UsarTakeProfit       = true;      // Utilizar Take Profit

input string GRUPO_14 = "===== 14. BREAK-EVEN E TRAILING STOP =====";      // 14. Break-Even e Trailing Stop
input bool   UsarBreakEven        = true;      // Ativar break-even
input double BreakEvenAtivacaoPips= 200.0;     // Lucro (pips) para acionar o break-even
input double BreakEvenTravaPips   = 20.0;      // Pips de lucro travados no break-even
input bool   UsarTrailingStop     = true;      // Ativar trailing stop
input double TrailingInicioPips   = 300.0;     // Lucro (pips) para iniciar o trailing
input double TrailingDistanciaPips= 200.0;     // Distancia do trailing (pips)
input double TrailingPassoPips    = 20.0;      // Passo minimo de ajuste do trailing (pips)

input string GRUPO_15 = "===== 15. LIMITES DIARIOS =====";                 // 15. Limites Diarios
input bool   UsarPerdaDiariaMax   = true;      // Ativar limite de perda diaria
input double PerdaDiariaMaxPct    = 3.0;       // Perda diaria maxima em % do saldo inicial do dia
input bool   UsarGanhoDiarioMeta  = false;     // Ativar meta de ganho diario
input double GanhoDiarioMetaPct   = 5.0;       // Meta de ganho diario em % do saldo inicial do dia
input bool   FecharAoAtingirLimite= true;      // Fechar posicoes ao atingir limite/meta do dia
input int    MaxPosicoesSimultaneas = 1;       // Maximo de posicoes abertas simultaneas
input int    MaxTradesPorDia      = 10;        // Maximo de trades por dia (0 = ilimitado)

input string GRUPO_16 = "===== 16. FILTROS DE MERCADO =====";              // 16. Filtros de Mercado
input bool   UsarFiltroSpread     = true;      // Ativar filtro de spread
input double SpreadMaximoPontos   = 30.0;      // Spread maximo aceito (em pontos)
input int    BarrasMinimasHistorico = 200;     // Barras minimas no historico para operar

input string GRUPO_17 = "===== 17. FECHAMENTO AUTOMATICO =====";           // 17. Fechamento Automatico
input bool   FecharNoFimDaJanela  = false;     // Fechar posicoes ao sair da janela de horario
input bool   FecharNaSexta        = false;     // Fechar posicoes na sexta-feira
input int    SextaFechamentoHora  = 20;        // Sexta - hora de fechamento
input int    SextaFechamentoMinuto= 0;         // Sexta - minuto de fechamento

input string GRUPO_18 = "===== 18. PAINEL VISUAL =====";                   // 18. Painel Visual
input bool   PainelAtivo          = true;      // Exibir painel on-chart (Comment)
input bool   LogDetalhado         = true;      // Gravar log detalhado no Experts

//==================================================================//
//  S03 - VARIAVEIS GLOBAIS E ESTRUTURAS                            //
//==================================================================//

//--- Fotografia dos indicadores no candle avaliado e no anterior
struct IndicatorSnapshot
  {
   bool     valido;          // true se todas as leituras foram bem sucedidas
   //--- Medias moveis exponenciais
   double   emaRapida;
   double   emaRapidaAnt;
   double   emaLenta;
   double   emaLentaAnt;
   //--- RSI
   double   rsi;
   double   rsiAnt;
   //--- MACD
   double   macdPrincipal;
   double   macdPrincipalAnt;
   double   macdSinal;
   double   macdSinalAnt;
   //--- ATR
   double   atr;
   double   atrAnt;
   //--- Bollinger
   double   bbSuperior;
   double   bbMedia;
   double   bbInferior;
   //--- ADX
   double   adx;
   double   adxMais;
   double   adxMenos;
   //--- Precos do candle avaliado
   double   fechamento;
   double   fechamentoAnt;
   double   abertura;
   double   maxima;
   double   minima;
  };

//--- Detalhamento do score por indicador (usado no painel)
struct ScoreBreakdown
  {
   double   ema;
   double   rsi;
   double   macd;
   double   bollinger;
   double   adx;
   double   atr;
   double   somaPesos;
   double   total;
  };

//--- Contexto de mercado / conta
int      g_digits          = 5;      // Casas decimais do simbolo
double   g_point           = 0.00001;// Valor de um ponto
int      g_pipMultiplier   = 1;      // 10 para corretoras de 3/5 digitos, 1 caso contrario
double   g_pipSize         = 0.0001; // Tamanho de 1 pip em preco
int      g_timeframe       = 0;      // Timeframe efetivo de analise
int      g_slippagePontos  = 30;     // Slippage convertido para pontos

//--- Controle de nova barra
datetime g_ultimaBarra     = 0;

//--- Contexto diario
int      g_diaCorrente     = 0;      // Data corrente no formato AAAAMMDD
double   g_saldoInicioDia  = 0.0;    // Saldo no inicio do dia
bool     g_limiteDiarioAtingido = false;
string   g_motivoLimite    = "";

//--- Estado exposto ao painel
double   g_scoreAtual      = 0.0;
string   g_motivoBloqueio  = "";
bool     g_permitidoAgora  = true;
ScoreBreakdown g_breakdown;
string   g_ultimaMensagem  = "";

//==================================================================//
//  S04 - UTILITARIOS GERAIS                                        //
//==================================================================//

//+------------------------------------------------------------------+
//| Remove espacos em branco no inicio e no fim de um texto.          |
//+------------------------------------------------------------------+
string TrimText(string texto)
  {
   StringTrimLeft(texto);
   StringTrimRight(texto);
   return(texto);
  }

//+------------------------------------------------------------------+
//| Divide uma string CSV em tokens nao vazios.                       |
//| Implementacao manual com StringFind/StringSubstr para maxima      |
//| compatibilidade entre builds do MQL4.                             |
//| Retorna a quantidade de tokens gravados em "saida".               |
//+------------------------------------------------------------------+
int SplitCsv(const string origem, string &saida[])
  {
   ArrayResize(saida, 0);
   int total = 0;
   int posicao = 0;
   int tamanho = StringLen(origem);
   if(tamanho <= 0)
      return(0);

   while(posicao <= tamanho)
     {
      int virgula = StringFind(origem, ",", posicao);
      string token;
      if(virgula < 0)
         token = StringSubstr(origem, posicao);
      else
         token = StringSubstr(origem, posicao, virgula - posicao);

      token = TrimText(token);
      if(StringLen(token) > 0)
        {
         total++;
         ArrayResize(saida, total);
         saida[total - 1] = token;
        }

      if(virgula < 0)
         break;
      posicao = virgula + 1;
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| Verifica se um valor inteiro pertence a uma lista CSV que aceita  |
//| valores isolados e intervalos. Exemplos validos:                  |
//|    "1,2,15-20,31"   "1-6,9,10-12"   "*"   ""                      |
//| Lista vazia ou "*" significa "sem restricao" (retorna true).      |
//+------------------------------------------------------------------+
bool MatchesCsvRange(const string csv, const int valor)
  {
   string limpo = TrimText(csv);
   if(StringLen(limpo) == 0)
      return(true);
   if(limpo == "*")
      return(true);

   string tokens[];
   int total = SplitCsv(limpo, tokens);
   if(total <= 0)
      return(true);

   for(int i = 0; i < total; i++)
     {
      string token = tokens[i];
      int traco = StringFind(token, "-", 1);   // inicia em 1 para nao confundir com sinal negativo
      if(traco > 0)
        {
         int inicio = (int)StringToInteger(TrimText(StringSubstr(token, 0, traco)));
         int fim    = (int)StringToInteger(TrimText(StringSubstr(token, traco + 1)));
         if(inicio > fim)
           {
            int troca = inicio;
            inicio = fim;
            fim = troca;
           }
         if(valor >= inicio && valor <= fim)
            return(true);
        }
      else
        {
         int unico = (int)StringToInteger(token);
         if(valor == unico)
            return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Converte um datetime para o inteiro AAAAMMDD.                     |
//+------------------------------------------------------------------+
int DateKey(const datetime t)
  {
   return(TimeYear(t) * 10000 + TimeMonth(t) * 100 + TimeDay(t));
  }

//+------------------------------------------------------------------+
//| Zera as horas de um datetime, devolvendo a meia-noite do dia.     |
//+------------------------------------------------------------------+
datetime DayStart(const datetime t)
  {
   return(t - (TimeHour(t) * 3600 + TimeMinute(t) * 60 + TimeSeconds(t)));
  }

//+------------------------------------------------------------------+
//| Limita um valor ao intervalo [minimo, maximo].                    |
//+------------------------------------------------------------------+
double Clip(const double valor, const double minimo, const double maximo)
  {
   if(valor < minimo)
      return(minimo);
   if(valor > maximo)
      return(maximo);
   return(valor);
  }

//+------------------------------------------------------------------+
//| Converte pips (na convencao do usuario) para distancia em preco.  |
//+------------------------------------------------------------------+
double PipsToPrice(const double pips)
  {
   return(pips * g_pipSize);
  }

//+------------------------------------------------------------------+
//| Converte distancia em preco para pips.                            |
//+------------------------------------------------------------------+
double PriceToPips(const double distancia)
  {
   if(g_pipSize <= 0.0)
      return(0.0);
   return(distancia / g_pipSize);
  }

//+------------------------------------------------------------------+
//| Distancia minima exigida pela corretora para SL/TP (em preco).    |
//+------------------------------------------------------------------+
double MinStopDistance()
  {
   double nivel = MarketInfo(Symbol(), MODE_STOPLEVEL) * g_point;
   double congelamento = MarketInfo(Symbol(), MODE_FREEZELEVEL) * g_point;
   if(congelamento > nivel)
      nivel = congelamento;
   if(nivel < g_point)
      nivel = g_point;
   return(nivel);
  }

//+------------------------------------------------------------------+
//| Spread atual em pontos.                                           |
//+------------------------------------------------------------------+
double CurrentSpreadPoints()
  {
   double spread = (Ask - Bid) / g_point;
   if(spread < 0.0)
      spread = 0.0;
   return(spread);
  }

//+------------------------------------------------------------------+
//| Registra mensagem no log de Experts (respeitando LogDetalhado).   |
//+------------------------------------------------------------------+
void LogInfo(const string mensagem)
  {
   g_ultimaMensagem = mensagem;
   if(LogDetalhado)
      Print("[MESA] ", mensagem);
  }

//+------------------------------------------------------------------+
//| Detecta a abertura de uma nova barra no timeframe de analise.     |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime barraAtual = iTime(Symbol(), g_timeframe, 0);
   if(barraAtual == 0)
      return(false);
   if(barraAtual != g_ultimaBarra)
     {
      g_ultimaBarra = barraAtual;
      return(true);
     }
   return(false);
  }

//==================================================================//
//  S05 - LEITURA DE INDICADORES                                    //
//==================================================================//

//+------------------------------------------------------------------+
//| ReadIndicators                                                    |
//| Preenche a struct IndicatorSnapshot com as leituras do candle     |
//| avaliado (shift = 1 se UsarCandleFechado, senao 0) e do candle    |
//| imediatamente anterior. Todos os indicadores sao chamados pela    |
//| API classica do MQL4, informando o shift diretamente.             |
//+------------------------------------------------------------------+
void ReadIndicators(IndicatorSnapshot &snap)
  {
   //--- inicializacao defensiva
   snap.valido            = false;
   snap.emaRapida         = 0.0;   snap.emaRapidaAnt     = 0.0;
   snap.emaLenta          = 0.0;   snap.emaLentaAnt      = 0.0;
   snap.rsi               = 0.0;   snap.rsiAnt           = 0.0;
   snap.macdPrincipal     = 0.0;   snap.macdPrincipalAnt = 0.0;
   snap.macdSinal         = 0.0;   snap.macdSinalAnt     = 0.0;
   snap.atr               = 0.0;   snap.atrAnt           = 0.0;
   snap.bbSuperior        = 0.0;   snap.bbMedia          = 0.0;  snap.bbInferior = 0.0;
   snap.adx               = 0.0;   snap.adxMais          = 0.0;  snap.adxMenos   = 0.0;
   snap.fechamento        = 0.0;   snap.fechamentoAnt    = 0.0;
   snap.abertura          = 0.0;   snap.maxima           = 0.0;  snap.minima     = 0.0;

   //--- shifts do candle avaliado e do anterior
   int sh  = (UsarCandleFechado ? 1 : 0);
   int shA = sh + 1;

   //--- historico suficiente?
   int barras = iBars(Symbol(), g_timeframe);
   if(barras < BarrasMinimasHistorico || barras <= shA)
      return;

   ResetLastError();

   //--- EMA rapida e lenta
   snap.emaRapida    = iMA(Symbol(), g_timeframe, EmaRapidaPeriodo, 0, MODE_EMA, EmaPrecoAplicado, sh);
   snap.emaRapidaAnt = iMA(Symbol(), g_timeframe, EmaRapidaPeriodo, 0, MODE_EMA, EmaPrecoAplicado, shA);
   snap.emaLenta     = iMA(Symbol(), g_timeframe, EmaLentaPeriodo,  0, MODE_EMA, EmaPrecoAplicado, sh);
   snap.emaLentaAnt  = iMA(Symbol(), g_timeframe, EmaLentaPeriodo,  0, MODE_EMA, EmaPrecoAplicado, shA);

   //--- RSI
   snap.rsi          = iRSI(Symbol(), g_timeframe, RsiPeriodo, RsiPrecoAplicado, sh);
   snap.rsiAnt       = iRSI(Symbol(), g_timeframe, RsiPeriodo, RsiPrecoAplicado, shA);

   //--- MACD (linha principal e linha de sinal)
   snap.macdPrincipal    = iMACD(Symbol(), g_timeframe, MacdRapida, MacdLenta, MacdSinal, PRICE_CLOSE, MODE_MAIN,   sh);
   snap.macdPrincipalAnt = iMACD(Symbol(), g_timeframe, MacdRapida, MacdLenta, MacdSinal, PRICE_CLOSE, MODE_MAIN,   shA);
   snap.macdSinal        = iMACD(Symbol(), g_timeframe, MacdRapida, MacdLenta, MacdSinal, PRICE_CLOSE, MODE_SIGNAL, sh);
   snap.macdSinalAnt     = iMACD(Symbol(), g_timeframe, MacdRapida, MacdLenta, MacdSinal, PRICE_CLOSE, MODE_SIGNAL, shA);

   //--- ATR
   snap.atr    = iATR(Symbol(), g_timeframe, AtrPeriodo, sh);
   snap.atrAnt = iATR(Symbol(), g_timeframe, AtrPeriodo, shA);

   //--- Bandas de Bollinger
   snap.bbSuperior = iBands(Symbol(), g_timeframe, BollingerPeriodo, BollingerDesvio, 0, PRICE_CLOSE, MODE_UPPER, sh);
   snap.bbMedia    = iBands(Symbol(), g_timeframe, BollingerPeriodo, BollingerDesvio, 0, PRICE_CLOSE, MODE_MAIN,  sh);
   snap.bbInferior = iBands(Symbol(), g_timeframe, BollingerPeriodo, BollingerDesvio, 0, PRICE_CLOSE, MODE_LOWER, sh);

   //--- ADX e as linhas direcionais
   snap.adx      = iADX(Symbol(), g_timeframe, AdxPeriodo, PRICE_CLOSE, MODE_MAIN,    sh);
   snap.adxMais  = iADX(Symbol(), g_timeframe, AdxPeriodo, PRICE_CLOSE, MODE_PLUSDI,  sh);
   snap.adxMenos = iADX(Symbol(), g_timeframe, AdxPeriodo, PRICE_CLOSE, MODE_MINUSDI, sh);

   //--- Precos
   snap.fechamento    = iClose(Symbol(), g_timeframe, sh);
   snap.fechamentoAnt = iClose(Symbol(), g_timeframe, shA);
   snap.abertura      = iOpen(Symbol(),  g_timeframe, sh);
   snap.maxima        = iHigh(Symbol(),  g_timeframe, sh);
   snap.minima        = iLow(Symbol(),   g_timeframe, sh);

   int erro = GetLastError();
   if(erro != 0)
     {
      LogInfo(StringFormat("Falha ao ler indicadores. Erro=%d", erro));
      return;
     }

   //--- validacao minima das leituras
   if(snap.fechamento <= 0.0 || snap.emaLenta <= 0.0 || snap.bbSuperior <= 0.0)
      return;

   snap.valido = true;
  }

//==================================================================//
//  S06 - MOTOR DE SINAL PONDERADO                                  //
//==================================================================//

//+------------------------------------------------------------------+
//| ComputeScore                                                      |
//|                                                                   |
//| Calcula um score direcional no intervalo [-100, +100] a partir    |
//| das leituras da struct IndicatorSnapshot.                         |
//|                                                                   |
//| METODO                                                            |
//| Cada indicador produz um sub-score normalizado em [-1, +1], onde  |
//| +1 = maximo vies comprador e -1 = maximo vies vendedor. O score   |
//| final e a media ponderada dos sub-scores pelos respectivos pesos  |
//| informados nos inputs, multiplicada por 100:                      |
//|                                                                   |
//|     score = 100 * SOMA(peso_i * subscore_i) / SOMA(peso_i)        |
//|                                                                   |
//| SUB-SCORES                                                        |
//|  EMA        : distancia (emaRapida - emaLenta) normalizada pelo   |
//|               ATR e dividida por EmaNormalizador. Cruzamentos     |
//|               recentes saturam o sub-score em +/-1.               |
//|  RSI        : modo tendencia -> (rsi - 50) / 50.                  |
//|               modo reversao  -> saturado em +1 na sobrevenda e    |
//|               em -1 na sobrecompra, invertendo o sinal no meio.   |
//|  MACD       : combinacao de tres componentes -                    |
//|               0.5 * sinal do histograma (principal - sinal)       |
//|             + 0.3 * posicao da linha principal frente ao zero     |
//|             + 0.2 * variacao do histograma (aceleracao).          |
//|  BOLLINGER  : posicao relativa do fechamento dentro das bandas,   |
//|               mapeada linearmente de -1 (banda inferior) a +1     |
//|               (banda superior). Invertida no modo reversao.       |
//|  ADX        : direcao dada por (+DI - -DI) multiplicada pela      |
//|               forca ADX/AdxEscala saturada em 1.                  |
//|  ATR        : impulso do candle (fechamento - fechamento anterior)|
//|               normalizado pelo proprio ATR e saturado em +/-1.    |
//|                                                                   |
//| O detalhamento por indicador e devolvido em "detalhe" para uso    |
//| no painel on-chart.                                               |
//+------------------------------------------------------------------+
double ComputeScore(const IndicatorSnapshot &snap, ScoreBreakdown &detalhe)
  {
   detalhe.ema       = 0.0;
   detalhe.rsi       = 0.0;
   detalhe.macd      = 0.0;
   detalhe.bollinger = 0.0;
   detalhe.adx       = 0.0;
   detalhe.atr       = 0.0;
   detalhe.somaPesos = 0.0;
   detalhe.total     = 0.0;

   if(!snap.valido)
      return(0.0);

   double soma = 0.0;
   double pesos = 0.0;

   //--- 1) EMA -----------------------------------------------------
   if(PesoEma > 0.0)
     {
      double sub = 0.0;
      double diferenca = snap.emaRapida - snap.emaLenta;
      double divisor = snap.atr * (EmaNormalizador > 0.0 ? EmaNormalizador : 1.0);
      if(divisor > 0.0)
         sub = Clip(diferenca / divisor, -1.0, 1.0);
      else
         sub = (diferenca > 0.0 ? 1.0 : (diferenca < 0.0 ? -1.0 : 0.0));

      //--- cruzamento recente satura o sub-score
      bool cruzouAcima  = (snap.emaRapidaAnt <= snap.emaLentaAnt && snap.emaRapida > snap.emaLenta);
      bool cruzouAbaixo = (snap.emaRapidaAnt >= snap.emaLentaAnt && snap.emaRapida < snap.emaLenta);
      if(cruzouAcima)
         sub = 1.0;
      if(cruzouAbaixo)
         sub = -1.0;

      detalhe.ema = sub;
      soma  += PesoEma * sub;
      pesos += PesoEma;
     }

   //--- 2) RSI -----------------------------------------------------
   if(PesoRsi > 0.0)
     {
      double sub = 0.0;
      if(RsiModoReversao)
        {
         if(snap.rsi <= RsiSobrevenda)
            sub = 1.0;
         else
            if(snap.rsi >= RsiSobrecompra)
               sub = -1.0;
            else
               sub = -Clip((snap.rsi - 50.0) / 50.0, -1.0, 1.0);
        }
      else
        {
         sub = Clip((snap.rsi - 50.0) / 50.0, -1.0, 1.0);
        }
      detalhe.rsi = sub;
      soma  += PesoRsi * sub;
      pesos += PesoRsi;
     }

   //--- 3) MACD ----------------------------------------------------
   if(PesoMacd > 0.0)
     {
      double histograma     = snap.macdPrincipal    - snap.macdSinal;
      double histogramaAnt  = snap.macdPrincipalAnt - snap.macdSinalAnt;

      double compCruz = (histograma > 0.0 ? 1.0 : (histograma < 0.0 ? -1.0 : 0.0));
      double compZero = (snap.macdPrincipal > 0.0 ? 1.0 : (snap.macdPrincipal < 0.0 ? -1.0 : 0.0));
      double compAcel = (histograma > histogramaAnt ? 1.0 : (histograma < histogramaAnt ? -1.0 : 0.0));

      double sub = Clip(0.5 * compCruz + 0.3 * compZero + 0.2 * compAcel, -1.0, 1.0);
      detalhe.macd = sub;
      soma  += PesoMacd * sub;
      pesos += PesoMacd;
     }

   //--- 4) BOLLINGER -----------------------------------------------
   if(PesoBollinger > 0.0)
     {
      double sub = 0.0;
      double largura = snap.bbSuperior - snap.bbInferior;
      if(largura > 0.0)
         sub = Clip(2.0 * (snap.fechamento - snap.bbMedia) / largura, -1.0, 1.0);
      if(BollingerModoReversao)
         sub = -sub;
      detalhe.bollinger = sub;
      soma  += PesoBollinger * sub;
      pesos += PesoBollinger;
     }

   //--- 5) ADX -----------------------------------------------------
   if(PesoAdx > 0.0)
     {
      double escala = (AdxEscala > 0.0 ? AdxEscala : 40.0);
      double forca = Clip(snap.adx / escala, 0.0, 1.0);
      double direcao = 0.0;
      if(snap.adxMais > snap.adxMenos)
         direcao = 1.0;
      else
         if(snap.adxMais < snap.adxMenos)
            direcao = -1.0;

      double sub = direcao * forca;
      detalhe.adx = sub;
      soma  += PesoAdx * sub;
      pesos += PesoAdx;
     }

   //--- 6) ATR (impulso normalizado) -------------------------------
   if(PesoAtr > 0.0)
     {
      double sub = 0.0;
      if(snap.atr > 0.0)
         sub = Clip((snap.fechamento - snap.fechamentoAnt) / snap.atr, -1.0, 1.0);
      detalhe.atr = sub;
      soma  += PesoAtr * sub;
      pesos += PesoAtr;
     }

   detalhe.somaPesos = pesos;
   if(pesos <= 0.0)
      return(0.0);

   detalhe.total = Clip(100.0 * soma / pesos, -100.0, 100.0);
   return(detalhe.total);
  }

//+------------------------------------------------------------------+
//| Aplica os filtros "duros" de indicador (ADX minimo e faixa ATR).  |
//| Retorna true se o mercado esta apto; caso contrario preenche o    |
//| motivo do bloqueio.                                               |
//+------------------------------------------------------------------+
bool PassesIndicatorGates(const IndicatorSnapshot &snap, string &motivo)
  {
   motivo = "";

   if(AdxMinimo > 0.0 && snap.adx < AdxMinimo)
     {
      motivo = StringFormat("ADX %.1f abaixo do minimo %.1f", snap.adx, AdxMinimo);
      return(false);
     }

   double atrPips = PriceToPips(snap.atr);

   if(AtrMinimoPips > 0.0 && atrPips < AtrMinimoPips)
     {
      motivo = StringFormat("ATR %.1f pips abaixo do minimo %.1f", atrPips, AtrMinimoPips);
      return(false);
     }

   if(AtrMaximoPips > 0.0 && atrPips > AtrMaximoPips)
     {
      motivo = StringFormat("ATR %.1f pips acima do maximo %.1f", atrPips, AtrMaximoPips);
      return(false);
     }

   return(true);
  }

//==================================================================//
//  S07 - FILTROS DE TEMPO                                          //
//==================================================================//

//+------------------------------------------------------------------+
//| Verifica se um minuto do dia esta dentro de uma janela,           |
//| tratando corretamente janelas que cruzam a meia-noite.            |
//|   inicio == fim  -> janela de 24 horas (sempre dentro)            |
//|   inicio <  fim  -> janela simples do mesmo dia                   |
//|   inicio >  fim  -> janela que cruza a meia-noite                 |
//+------------------------------------------------------------------+
bool IsInsideMinuteWindow(const int minutoAtual, const int minutoInicio, const int minutoFim)
  {
   if(minutoInicio == minutoFim)
      return(true);
   if(minutoInicio < minutoFim)
      return(minutoAtual >= minutoInicio && minutoAtual < minutoFim);
   //--- janela cruzando a meia-noite (ex.: 22:00 -> 06:00)
   return(minutoAtual >= minutoInicio || minutoAtual < minutoFim);
  }

//+------------------------------------------------------------------+
//| Filtro 1 - Janela de horario HoraInicio:MinutoInicio ate          |
//|            HoraFim:MinutoFim (inclui cruzamento de meia-noite).   |
//+------------------------------------------------------------------+
bool PassesHourFilter(const datetime t)
  {
   if(!UsarFiltroHorario)
      return(true);

   int agora  = TimeHour(t) * 60 + TimeMinute(t);
   int inicio = HoraInicio * 60 + MinutoInicio;
   int fim    = HoraFim    * 60 + MinutoFim;

   return(IsInsideMinuteWindow(agora, inicio, fim));
  }

//+------------------------------------------------------------------+
//| Filtro 2 - Dia da semana (sete booleanos independentes).          |
//| TimeDayOfWeek: 0 = domingo ... 6 = sabado                         |
//+------------------------------------------------------------------+
bool PassesWeekdayFilter(const datetime t)
  {
   int dia = TimeDayOfWeek(t);
   switch(dia)
     {
      case 0:  return(OperarDomingo);
      case 1:  return(OperarSegunda);
      case 2:  return(OperarTerca);
      case 3:  return(OperarQuarta);
      case 4:  return(OperarQuinta);
      case 5:  return(OperarSexta);
      case 6:  return(OperarSabado);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Filtro 3 - Dia do mes via CSV com intervalos ("1,2,15-20,31").    |
//+------------------------------------------------------------------+
bool PassesMonthDayFilter(const datetime t)
  {
   if(!UsarFiltroDiaMes)
      return(true);
   return(MatchesCsvRange(DiasDoMesPermitidos, TimeDay(t)));
  }

//+------------------------------------------------------------------+
//| Filtro 4 - Mes via CSV com intervalos ("1-6,9,10-12").            |
//+------------------------------------------------------------------+
bool PassesMonthFilter(const datetime t)
  {
   if(!UsarFiltroMes)
      return(true);
   return(MatchesCsvRange(MesesPermitidos, TimeMonth(t)));
  }

//+------------------------------------------------------------------+
//| Filtro 5 - Ano minimo e ano maximo.                               |
//+------------------------------------------------------------------+
bool PassesYearFilter(const datetime t)
  {
   if(!UsarFiltroAno)
      return(true);
   int ano = TimeYear(t);
   if(ano < AnoMinimo)
      return(false);
   if(ano > AnoMaximo)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Filtro 6 - Blackout de datas.                                     |
//| Formato CSV AAAA.MM.DD, aceitando tambem intervalos escritos      |
//| como "AAAA.MM.DD-AAAA.MM.DD".                                     |
//| Retorna true se a data ESTIVER bloqueada.                         |
//+------------------------------------------------------------------+
bool IsBlackoutDate(const datetime t)
  {
   if(!UsarBlackoutDatas)
      return(false);

   string limpo = TrimText(DatasBloqueadas);
   if(StringLen(limpo) == 0)
      return(false);

   datetime diaAtual = DayStart(t);

   string tokens[];
   int total = SplitCsv(limpo, tokens);
   for(int i = 0; i < total; i++)
     {
      string token = tokens[i];
      int traco = StringFind(token, "-", 1);
      if(traco > 0)
        {
         //--- intervalo de datas
         string textoA = TrimText(StringSubstr(token, 0, traco));
         string textoB = TrimText(StringSubstr(token, traco + 1));
         datetime dataA = StringToTime(textoA);
         datetime dataB = StringToTime(textoB);
         if(dataA <= 0 || dataB <= 0)
            continue;
         dataA = DayStart(dataA);
         dataB = DayStart(dataB);
         if(dataA > dataB)
           {
            datetime troca = dataA;
            dataA = dataB;
            dataB = troca;
           }
         if(diaAtual >= dataA && diaAtual <= dataB)
            return(true);
        }
      else
        {
         //--- data isolada
         datetime data = StringToTime(token);
         if(data <= 0)
            continue;
         if(DayStart(data) == diaAtual)
            return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Filtro 7 - Sessoes de mercado (Asia / Londres / Nova York).       |
//| O horario do servidor e convertido para GMT usando o input        |
//| OffsetGmtServidor. A operacao e liberada se o horario GMT cair    |
//| dentro de PELO MENOS UMA das sessoes habilitadas.                 |
//+------------------------------------------------------------------+
bool PassesSessionFilter(const datetime t, string &sessaoAtiva)
  {
   sessaoAtiva = "";
   if(!UsarFiltroSessao)
     {
      sessaoAtiva = "filtro desligado";
      return(true);
     }

   //--- converte a hora do servidor para GMT
   datetime gmt = t - (int)MathRound(OffsetGmtServidor * 3600.0);
   int minutoGmt = TimeHour(gmt) * 60 + TimeMinute(gmt);

   bool liberado = false;

   if(SessaoAsia && IsInsideMinuteWindow(minutoGmt, AsiaInicioGmt * 60, AsiaFimGmt * 60))
     {
      liberado = true;
      sessaoAtiva = "Asia";
     }

   if(SessaoLondres && IsInsideMinuteWindow(minutoGmt, LondresInicioGmt * 60, LondresFimGmt * 60))
     {
      liberado = true;
      sessaoAtiva = (StringLen(sessaoAtiva) > 0 ? sessaoAtiva + "+Londres" : "Londres");
     }

   if(SessaoNovaYork && IsInsideMinuteWindow(minutoGmt, NovaYorkInicioGmt * 60, NovaYorkFimGmt * 60))
     {
      liberado = true;
      sessaoAtiva = (StringLen(sessaoAtiva) > 0 ? sessaoAtiva + "+NovaYork" : "NovaYork");
     }

   if(!liberado)
      sessaoAtiva = StringFormat("fora de sessao (GMT %02d:%02d)", TimeHour(gmt), TimeMinute(gmt));

   return(liberado);
  }

//+------------------------------------------------------------------+
//| IsTradingAllowed                                                  |
//|                                                                   |
//| Agrega TODOS os filtros de tempo e devolve, por referencia, o     |
//| motivo exato do bloqueio. A ordem de avaliacao vai do filtro      |
//| mais amplo (ano) ao mais estreito (sessao), de modo que o motivo  |
//| reportado seja o mais informativo possivel.                       |
//+------------------------------------------------------------------+
bool IsTradingAllowed(const datetime t, string &motivo)
  {
   motivo = "";

   //--- 1) Ano
   if(!PassesYearFilter(t))
     {
      motivo = StringFormat("Ano %d fora da faixa permitida [%d..%d]", TimeYear(t), AnoMinimo, AnoMaximo);
      return(false);
     }

   //--- 2) Mes
   if(!PassesMonthFilter(t))
     {
      motivo = StringFormat("Mes %d nao permitido (lista: %s)", TimeMonth(t), MesesPermitidos);
      return(false);
     }

   //--- 3) Dia do mes
   if(!PassesMonthDayFilter(t))
     {
      motivo = StringFormat("Dia %d nao permitido (lista: %s)", TimeDay(t), DiasDoMesPermitidos);
      return(false);
     }

   //--- 4) Dia da semana
   if(!PassesWeekdayFilter(t))
     {
      motivo = StringFormat("Dia da semana bloqueado (%s)", WeekdayName(TimeDayOfWeek(t)));
      return(false);
     }

   //--- 5) Blackout de datas
   if(IsBlackoutDate(t))
     {
      motivo = StringFormat("Data em blackout (%s)", TimeToString(t, TIME_DATE));
      return(false);
     }

   //--- 6) Janela de horario
   if(!PassesHourFilter(t))
     {
      motivo = StringFormat("Fora da janela %02d:%02d-%02d:%02d (agora %02d:%02d)",
                            HoraInicio, MinutoInicio, HoraFim, MinutoFim,
                            TimeHour(t), TimeMinute(t));
      return(false);
     }

   //--- 7) Sessao de mercado
   string sessao = "";
   if(!PassesSessionFilter(t, sessao))
     {
      motivo = StringFormat("Sessao bloqueada: %s", sessao);
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Nome do dia da semana em portugues.                               |
//+------------------------------------------------------------------+
string WeekdayName(const int dia)
  {
   switch(dia)
     {
      case 0: return("Domingo");
      case 1: return("Segunda");
      case 2: return("Terca");
      case 3: return("Quarta");
      case 4: return("Quinta");
      case 5: return("Sexta");
      case 6: return("Sabado");
     }
   return("?");
  }

//==================================================================//
//  S08 - ESTATISTICAS DIARIAS                                      //
//==================================================================//

//+------------------------------------------------------------------+
//| Conta as posicoes abertas pertencentes a este EA neste simbolo.   |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int total = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != MagicNumber)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      total++;
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| Conta posicoes abertas em uma direcao especifica (OP_BUY/OP_SELL).|
//+------------------------------------------------------------------+
int CountOpenPositionsByType(const int tipo)
  {
   int total = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      if(OrderType() == tipo)
         total++;
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| Lucro flutuante das posicoes abertas do EA (com swap e comissao). |
//+------------------------------------------------------------------+
double FloatingProfit()
  {
   double total = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      total += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| Resultado realizado no dia corrente (historico de ordens).        |
//+------------------------------------------------------------------+
double ClosedProfitToday()
  {
   double total = 0.0;
   int hoje = DateKey(TimeCurrent());

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(DateKey(OrderCloseTime()) != hoje)
         continue;
      total += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| Quantidade de trades abertos no dia corrente (historico + vivos). |
//+------------------------------------------------------------------+
int CountTradesToday()
  {
   int hoje = DateKey(TimeCurrent());
   int total = 0;

   //--- ordens ja encerradas
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(DateKey(OrderOpenTime()) == hoje)
         total++;
     }

   //--- ordens ainda abertas
   for(int j = OrdersTotal() - 1; j >= 0; j--)
     {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(DateKey(OrderOpenTime()) == hoje)
         total++;
     }

   return(total);
  }

//+------------------------------------------------------------------+
//| Resultado do dia (realizado + flutuante) em moeda da conta.       |
//+------------------------------------------------------------------+
double DailyPnL()
  {
   return(ClosedProfitToday() + FloatingProfit());
  }

//+------------------------------------------------------------------+
//| Resultado do dia em percentual do saldo do inicio do dia.         |
//+------------------------------------------------------------------+
double DailyPnLPercent()
  {
   if(g_saldoInicioDia <= 0.0)
      return(0.0);
   return(100.0 * DailyPnL() / g_saldoInicioDia);
  }

//+------------------------------------------------------------------+
//| Atualiza o contexto diario, reiniciando contadores na virada.     |
//+------------------------------------------------------------------+
void UpdateDailyContext()
  {
   int hoje = DateKey(TimeCurrent());
   if(hoje != g_diaCorrente)
     {
      g_diaCorrente          = hoje;
      g_saldoInicioDia       = AccountBalance();
      g_limiteDiarioAtingido = false;
      g_motivoLimite         = "";
      LogInfo(StringFormat("Novo dia de negociacao: %s | saldo inicial %.2f",
                           TimeToString(TimeCurrent(), TIME_DATE), g_saldoInicioDia));
     }

   if(g_saldoInicioDia <= 0.0)
      g_saldoInicioDia = AccountBalance();
  }

//+------------------------------------------------------------------+
//| Avalia limite de perda e meta de ganho diarios.                   |
//| Retorna true se o EA ainda pode abrir novas posicoes.             |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
  {
   double pct = DailyPnLPercent();

   if(UsarPerdaDiariaMax && PerdaDiariaMaxPct > 0.0 && pct <= -PerdaDiariaMaxPct)
     {
      if(!g_limiteDiarioAtingido)
        {
         g_limiteDiarioAtingido = true;
         g_motivoLimite = StringFormat("Perda diaria maxima atingida (%.2f%% <= -%.2f%%)", pct, PerdaDiariaMaxPct);
         LogInfo(g_motivoLimite);
         if(FecharAoAtingirLimite)
            CloseAllPositions("limite de perda diaria");
        }
      return(false);
     }

   if(UsarGanhoDiarioMeta && GanhoDiarioMetaPct > 0.0 && pct >= GanhoDiarioMetaPct)
     {
      if(!g_limiteDiarioAtingido)
        {
         g_limiteDiarioAtingido = true;
         g_motivoLimite = StringFormat("Meta de ganho diario atingida (%.2f%% >= %.2f%%)", pct, GanhoDiarioMetaPct);
         LogInfo(g_motivoLimite);
         if(FecharAoAtingirLimite)
            CloseAllPositions("meta de ganho diario");
        }
      return(false);
     }

   if(g_limiteDiarioAtingido)
      return(false);

   return(true);
  }

//==================================================================//
//  S09 - GESTAO DE RISCO E VOLUME                                  //
//==================================================================//

//+------------------------------------------------------------------+
//| Normaliza o volume respeitando MODE_LOTSTEP/MINLOT/MAXLOT e o     |
//| teto configurado pelo usuario.                                    |
//+------------------------------------------------------------------+
double NormalizeLots(double lotes)
  {
   double loteMinimo = MarketInfo(Symbol(), MODE_MINLOT);
   double loteMaximo = MarketInfo(Symbol(), MODE_MAXLOT);
   double passoLote  = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(loteMinimo <= 0.0)
      loteMinimo = 0.01;
   if(loteMaximo <= 0.0)
      loteMaximo = 100.0;
   if(passoLote <= 0.0)
      passoLote = 0.01;

   //--- teto definido pelo usuario
   if(LoteMaximoPermitido > 0.0 && loteMaximo > LoteMaximoPermitido)
      loteMaximo = LoteMaximoPermitido;

   //--- alinha ao passo (sempre para baixo, evitando exceder o risco)
   lotes = MathFloor(lotes / passoLote + 0.0000001) * passoLote;

   if(lotes < loteMinimo)
      lotes = loteMinimo;
   if(lotes > loteMaximo)
      lotes = loteMaximo;

   //--- quantidade de casas decimais derivada do passo
   int casas = 2;
   if(passoLote >= 1.0)
      casas = 0;
   else
      if(passoLote >= 0.1)
         casas = 1;
      else
         if(passoLote >= 0.01)
            casas = 2;
         else
            casas = 3;

   return(NormalizeDouble(lotes, casas));
  }

//+------------------------------------------------------------------+
//| Valor monetario de 1 ponto para 1 lote no simbolo corrente.       |
//+------------------------------------------------------------------+
double ValuePerPointPerLot()
  {
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return(0.0);

   return(tickValue * (g_point / tickSize));
  }

//+------------------------------------------------------------------+
//| ComputeLotSize                                                    |
//| Modo lote fixo  : devolve LoteFixo normalizado.                   |
//| Modo risco %    : deriva o volume da distancia do stop de forma   |
//|                   que a perda maxima seja RiscoPorTradePct % do   |
//|                   saldo.                                          |
//+------------------------------------------------------------------+
double ComputeLotSize(const double distanciaStop)
  {
   if(ModoVolume == VOLUME_LOTE_FIXO)
      return(NormalizeLots(LoteFixo));

   if(distanciaStop <= 0.0)
     {
      LogInfo("Distancia de stop invalida para o calculo de risco. Usando lote fixo.");
      return(NormalizeLots(LoteFixo));
     }

   double valorPonto = ValuePerPointPerLot();
   if(valorPonto <= 0.0)
     {
      LogInfo("Nao foi possivel obter TICKVALUE/TICKSIZE. Usando lote fixo.");
      return(NormalizeLots(LoteFixo));
     }

   double saldo = AccountBalance();
   double riscoMonetario = saldo * (RiscoPorTradePct / 100.0);
   double stopEmPontos = distanciaStop / g_point;

   if(stopEmPontos <= 0.0)
      return(NormalizeLots(LoteFixo));

   double lotes = riscoMonetario / (stopEmPontos * valorPonto);
   return(NormalizeLots(lotes));
  }

//+------------------------------------------------------------------+
//| Distancia do Stop Loss em preco (ATR ou pontos fixos).            |
//+------------------------------------------------------------------+
double ComputeStopDistance(const IndicatorSnapshot &snap)
  {
   double distancia = 0.0;

   if(ModoStop == STOP_MULTIPLO_ATR)
     {
      if(snap.atr > 0.0)
         distancia = snap.atr * StopAtrMultiplicador;
     }
   else
     {
      distancia = PipsToPrice(StopLossPips);
     }

   //--- respeita a distancia minima da corretora
   double minimo = MinStopDistance();
   if(distancia > 0.0 && distancia < minimo)
      distancia = minimo;

   return(distancia);
  }

//+------------------------------------------------------------------+
//| Distancia do Take Profit em preco (ATR ou pontos fixos).          |
//+------------------------------------------------------------------+
double ComputeTakeDistance(const IndicatorSnapshot &snap)
  {
   if(!UsarTakeProfit)
      return(0.0);

   double distancia = 0.0;

   if(ModoStop == STOP_MULTIPLO_ATR)
     {
      if(snap.atr > 0.0)
         distancia = snap.atr * TakeAtrMultiplicador;
     }
   else
     {
      distancia = PipsToPrice(TakeProfitPips);
     }

   double minimo = MinStopDistance();
   if(distancia > 0.0 && distancia < minimo)
      distancia = minimo;

   return(distancia);
  }

//+------------------------------------------------------------------+
//| Filtro de spread. Retorna true se o spread esta aceitavel.        |
//+------------------------------------------------------------------+
bool PassesSpreadFilter(string &motivo)
  {
   motivo = "";
   if(!UsarFiltroSpread)
      return(true);

   double spread = CurrentSpreadPoints();
   if(SpreadMaximoPontos > 0.0 && spread > SpreadMaximoPontos)
     {
      motivo = StringFormat("Spread %.1f pts acima do maximo %.1f pts", spread, SpreadMaximoPontos);
      return(false);
     }
   return(true);
  }

//==================================================================//
//  S10 - EXECUCAO DE ORDENS                                        //
//==================================================================//

//+------------------------------------------------------------------+
//| Indica se um erro de negociacao permite nova tentativa.           |
//+------------------------------------------------------------------+
bool IsRetriableError(const int erro)
  {
   switch(erro)
     {
      case 4:    // servidor ocupado
      case 6:    // sem conexao
      case 128:  // tempo de transacao esgotado
      case 129:  // preco invalido
      case 130:  // stops invalidos (pode ser transitorio apos requote)
      case 135:  // preco mudou
      case 136:  // sem cotacoes
      case 137:  // corretora ocupada
      case 138:  // requote
      case 146:  // subsistema de negociacao ocupado
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Texto legivel para os codigos de erro mais comuns.                |
//+------------------------------------------------------------------+
string TradeErrorText(const int erro)
  {
   switch(erro)
     {
      case 0:   return("sem erro");
      case 1:   return("sem alteracao no pedido");
      case 2:   return("erro comum");
      case 3:   return("parametros invalidos");
      case 4:   return("servidor ocupado");
      case 6:   return("sem conexao");
      case 8:   return("pedidos frequentes demais");
      case 64:  return("conta bloqueada");
      case 65:  return("numero de conta invalido");
      case 128: return("tempo de transacao esgotado");
      case 129: return("preco invalido");
      case 130: return("stops invalidos");
      case 131: return("volume invalido");
      case 132: return("mercado fechado");
      case 133: return("negociacao desabilitada");
      case 134: return("dinheiro insuficiente");
      case 135: return("preco mudou");
      case 136: return("sem cotacoes");
      case 137: return("corretora ocupada");
      case 138: return("requote");
      case 139: return("ordem bloqueada");
      case 145: return("modificacao proibida (ordem muito proxima do mercado)");
      case 146: return("subsistema de negociacao ocupado");
      case 147: return("expiracao nao permitida");
      case 148: return("excesso de ordens abertas/pendentes");
     }
   return(StringFormat("erro %d", erro));
  }

//+------------------------------------------------------------------+
//| Ajusta os niveis de SL/TP para respeitar a distancia minima       |
//| exigida pela corretora em relacao ao preco corrente.              |
//+------------------------------------------------------------------+
void AdjustStopsToBroker(const int cmd, const double preco, double &sl, double &tp)
  {
   double minimo = MinStopDistance();

   if(cmd == OP_BUY)
     {
      if(sl > 0.0 && (preco - sl) < minimo)
         sl = preco - minimo;
      if(tp > 0.0 && (tp - preco) < minimo)
         tp = preco + minimo;
     }
   else
     {
      if(sl > 0.0 && (sl - preco) < minimo)
         sl = preco + minimo;
      if(tp > 0.0 && (preco - tp) < minimo)
         tp = preco - minimo;
     }

   if(sl > 0.0)
      sl = NormalizeDouble(sl, g_digits);
   if(tp > 0.0)
      tp = NormalizeDouble(tp, g_digits);
  }

//+------------------------------------------------------------------+
//| ExecuteEntry                                                      |
//| Abre uma posicao a mercado com retry, tratando GetLastError() e   |
//| chamando RefreshRates() antes de cada tentativa.                  |
//+------------------------------------------------------------------+
bool ExecuteEntry(const int cmd, const IndicatorSnapshot &snap)
  {
   double distanciaStop = ComputeStopDistance(snap);
   double distanciaTake = ComputeTakeDistance(snap);
   double lotes = ComputeLotSize(distanciaStop);

   if(lotes <= 0.0)
     {
      LogInfo("Volume calculado invalido. Entrada abortada.");
      return(false);
     }

   //--- checagem de margem
   ResetLastError();
   double margemLivre = AccountFreeMarginCheck(Symbol(), cmd, lotes);
   int erroMargem = GetLastError();
   if(margemLivre <= 0.0 || erroMargem == 134)
     {
      LogInfo(StringFormat("Margem insuficiente para %.2f lotes. Entrada abortada.", lotes));
      return(false);
     }

   int tentativas = (MaxTentativasEnvio > 0 ? MaxTentativasEnvio : 1);

   for(int tentativa = 1; tentativa <= tentativas; tentativa++)
     {
      if(IsStopped())
         return(false);

      if(!IsTradeAllowed())
        {
         Sleep(PausaEntreTentativasMs);
         continue;
        }

      RefreshRates();

      double preco = (cmd == OP_BUY ? Ask : Bid);
      preco = NormalizeDouble(preco, g_digits);

      double sl = 0.0;
      double tp = 0.0;

      if(distanciaStop > 0.0)
         sl = (cmd == OP_BUY ? preco - distanciaStop : preco + distanciaStop);
      if(distanciaTake > 0.0)
         tp = (cmd == OP_BUY ? preco + distanciaTake : preco - distanciaTake);

      AdjustStopsToBroker(cmd, preco, sl, tp);

      double slEnvio = (EnviarStopsSeparados ? 0.0 : sl);
      double tpEnvio = (EnviarStopsSeparados ? 0.0 : tp);

      ResetLastError();

      int ticket = OrderSend(Symbol(),
                             cmd,
                             lotes,
                             preco,
                             g_slippagePontos,
                             slEnvio,
                             tpEnvio,
                             ComentarioOrdem,
                             MagicNumber,
                             0,
                             (cmd == OP_BUY ? clrDodgerBlue : clrOrangeRed));

      if(ticket > 0)
        {
         LogInfo(StringFormat("Ordem %s enviada. Ticket=%d Lote=%.2f Preco=%s SL=%s TP=%s",
                              (cmd == OP_BUY ? "COMPRA" : "VENDA"),
                              ticket, lotes,
                              DoubleToString(preco, g_digits),
                              DoubleToString(sl, g_digits),
                              DoubleToString(tp, g_digits)));

         //--- contas ECN: aplica SL/TP apos a abertura
         if(EnviarStopsSeparados && (sl > 0.0 || tp > 0.0))
            ApplyStopsToTicket(ticket, sl, tp);

         return(true);
        }

      int erro = GetLastError();
      LogInfo(StringFormat("Falha no OrderSend (tentativa %d/%d): %s",
                           tentativa, tentativas, TradeErrorText(erro)));

      if(!IsRetriableError(erro))
         return(false);

      Sleep(PausaEntreTentativasMs);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Aplica SL/TP a um ticket ja aberto (fluxo ECN).                   |
//+------------------------------------------------------------------+
bool ApplyStopsToTicket(const int ticket, const double sl, const double tp)
  {
   int tentativas = (MaxTentativasEnvio > 0 ? MaxTentativasEnvio : 1);

   for(int tentativa = 1; tentativa <= tentativas; tentativa++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         return(false);

      RefreshRates();
      ResetLastError();

      if(OrderModify(ticket,
                     OrderOpenPrice(),
                     NormalizeDouble(sl, g_digits),
                     NormalizeDouble(tp, g_digits),
                     0,
                     clrGold))
         return(true);

      int erro = GetLastError();
      if(erro == 1)   // nenhuma alteracao necessaria
         return(true);

      LogInfo(StringFormat("Falha ao aplicar SL/TP no ticket %d: %s", ticket, TradeErrorText(erro)));

      if(!IsRetriableError(erro))
         return(false);

      Sleep(PausaEntreTentativasMs);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Fecha uma posicao selecionada, com retry.                         |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(const int ticket)
  {
   int tentativas = (MaxTentativasEnvio > 0 ? MaxTentativasEnvio : 1);

   for(int tentativa = 1; tentativa <= tentativas; tentativa++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         return(false);

      if(OrderCloseTime() != 0)
         return(true);   // ja encerrada

      if(!IsTradeAllowed())
        {
         Sleep(PausaEntreTentativasMs);
         continue;
        }

      RefreshRates();

      double preco = (OrderType() == OP_BUY ? Bid : Ask);
      preco = NormalizeDouble(preco, g_digits);

      ResetLastError();

      if(OrderClose(ticket, OrderLots(), preco, g_slippagePontos, clrGray))
        {
         LogInfo(StringFormat("Posicao %d encerrada em %s", ticket, DoubleToString(preco, g_digits)));
         return(true);
        }

      int erro = GetLastError();
      LogInfo(StringFormat("Falha ao fechar ticket %d (tentativa %d/%d): %s",
                           ticket, tentativa, tentativas, TradeErrorText(erro)));

      if(!IsRetriableError(erro))
         return(false);

      Sleep(PausaEntreTentativasMs);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Fecha todas as posicoes do EA neste simbolo.                      |
//+------------------------------------------------------------------+
int CloseAllPositions(const string motivo)
  {
   int fechadas = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      int ticket = OrderTicket();
      if(ClosePositionByTicket(ticket))
         fechadas++;
     }

   if(fechadas > 0)
      LogInfo(StringFormat("%d posicao(oes) encerrada(s). Motivo: %s", fechadas, motivo));

   return(fechadas);
  }

//==================================================================//
//  S11 - GESTAO DE POSICOES ABERTAS                                //
//==================================================================//

//+------------------------------------------------------------------+
//| Aplica break-even e trailing stop a todas as posicoes do EA.      |
//| Executado a cada tick (nao depende de nova barra).                |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   if(!UsarBreakEven && !UsarTrailingStop)
      return;

   double passoTrailing = PipsToPrice(TrailingPassoPips);
   double minimoBroker  = MinStopDistance();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;

      int tipo = OrderType();
      if(tipo != OP_BUY && tipo != OP_SELL)
         continue;

      int    ticket    = OrderTicket();
      double abertura  = OrderOpenPrice();
      double slAtual   = OrderStopLoss();
      double tpAtual   = OrderTakeProfit();
      double novoSl    = slAtual;

      RefreshRates();
      double precoAtual = (tipo == OP_BUY ? Bid : Ask);

      //--- lucro corrente em preco
      double lucro = (tipo == OP_BUY ? (precoAtual - abertura) : (abertura - precoAtual));

      //--- 1) BREAK-EVEN ------------------------------------------
      if(UsarBreakEven && BreakEvenAtivacaoPips > 0.0)
        {
         double gatilho = PipsToPrice(BreakEvenAtivacaoPips);
         double trava   = PipsToPrice(BreakEvenTravaPips);

         if(lucro >= gatilho)
           {
            double alvoSl = (tipo == OP_BUY ? abertura + trava : abertura - trava);

            if(tipo == OP_BUY)
              {
               if(novoSl < alvoSl - g_point * 0.5)
                  novoSl = alvoSl;
              }
            else
              {
               if(novoSl <= 0.0 || novoSl > alvoSl + g_point * 0.5)
                  novoSl = alvoSl;
              }
           }
        }

      //--- 2) TRAILING STOP ---------------------------------------
      if(UsarTrailingStop && TrailingDistanciaPips > 0.0)
        {
         double gatilhoTrailing = PipsToPrice(TrailingInicioPips);
         double distancia       = PipsToPrice(TrailingDistanciaPips);

         if(lucro >= gatilhoTrailing)
           {
            double alvoSl = (tipo == OP_BUY ? precoAtual - distancia : precoAtual + distancia);

            if(tipo == OP_BUY)
              {
               if(novoSl <= 0.0 || alvoSl - novoSl >= passoTrailing)
                  if(alvoSl > novoSl)
                     novoSl = alvoSl;
              }
            else
              {
               if(novoSl <= 0.0 || novoSl - alvoSl >= passoTrailing)
                  if(novoSl <= 0.0 || alvoSl < novoSl)
                     novoSl = alvoSl;
              }
           }
        }

      //--- 3) VALIDACAO E ENVIO -----------------------------------
      if(novoSl <= 0.0)
         continue;

      //--- nunca colocar o stop do lado errado do preco
      if(tipo == OP_BUY && novoSl >= precoAtual - minimoBroker)
         continue;
      if(tipo == OP_SELL && novoSl <= precoAtual + minimoBroker)
         continue;

      novoSl = NormalizeDouble(novoSl, g_digits);
      double slComparacao = NormalizeDouble(slAtual, g_digits);

      if(MathAbs(novoSl - slComparacao) < g_point * 0.5)
         continue;   // nada mudou

      ResetLastError();
      if(!OrderModify(ticket, abertura, novoSl, NormalizeDouble(tpAtual, g_digits), 0, clrLime))
        {
         int erro = GetLastError();
         if(erro != 1)
            LogInfo(StringFormat("Falha ao ajustar stop do ticket %d: %s", ticket, TradeErrorText(erro)));
        }
      else
        {
         LogInfo(StringFormat("Stop do ticket %d movido para %s", ticket, DoubleToString(novoSl, g_digits)));
        }
     }
  }

//+------------------------------------------------------------------+
//| Regras de fechamento automatico por horario.                      |
//| Retorna true se alguma posicao foi encerrada.                     |
//+------------------------------------------------------------------+
bool CheckAutoClose()
  {
   datetime agora = TimeCurrent();

   //--- 1) fechamento na sexta-feira
   if(FecharNaSexta && TimeDayOfWeek(agora) == 5)
     {
      int minutoAtual = TimeHour(agora) * 60 + TimeMinute(agora);
      int minutoAlvo  = SextaFechamentoHora * 60 + SextaFechamentoMinuto;
      if(minutoAtual >= minutoAlvo)
        {
         if(CountOpenPositions() > 0)
           {
            CloseAllPositions("fechamento programado de sexta-feira");
            return(true);
           }
        }
     }

   //--- 2) fechamento ao sair da janela de horario
   if(FecharNoFimDaJanela && UsarFiltroHorario)
     {
      if(!PassesHourFilter(agora))
        {
         if(CountOpenPositions() > 0)
           {
            CloseAllPositions("fim da janela de horario");
            return(true);
           }
        }
     }

   return(false);
  }

//==================================================================//
//  S12 - PAINEL ON-CHART                                           //
//==================================================================//

//+------------------------------------------------------------------+
//| Rotulo LIBERADO/BLOQUEADO para o painel.                          |
//+------------------------------------------------------------------+
string StatusLabel(const bool liberado)
  {
   return(liberado ? "LIBERADO " : "BLOQUEADO");
  }

//+------------------------------------------------------------------+
//| Monta e exibe o painel de acompanhamento via Comment().           |
//+------------------------------------------------------------------+
void UpdatePanel(const IndicatorSnapshot &snap)
  {
   if(!PainelAtivo)
      return;

   datetime agora = TimeCurrent();

   //--- estados individuais dos filtros
   bool okAno     = PassesYearFilter(agora);
   bool okMes     = PassesMonthFilter(agora);
   bool okDiaMes  = PassesMonthDayFilter(agora);
   bool okSemana  = PassesWeekdayFilter(agora);
   bool okBlack   = !IsBlackoutDate(agora);
   bool okHora    = PassesHourFilter(agora);

   string sessao = "";
   bool okSessao = PassesSessionFilter(agora, sessao);

   string motivoSpread = "";
   bool okSpread = PassesSpreadFilter(motivoSpread);

   string motivoGate = "";
   bool okGates = PassesIndicatorGates(snap, motivoGate);

   //--- estatisticas
   int    posicoes   = CountOpenPositions();
   int    tradesHoje = CountTradesToday();
   double pnlDia     = DailyPnL();
   double pnlDiaPct  = DailyPnLPercent();
   double spread     = CurrentSpreadPoints();

   bool okPosicoes = (MaxPosicoesSimultaneas <= 0 || posicoes < MaxPosicoesSimultaneas);
   bool okTrades   = (MaxTradesPorDia <= 0 || tradesHoje < MaxTradesPorDia);
   bool okDiario   = !g_limiteDiarioAtingido;

   //--- direcao sugerida pelo score
   string direcao = "NEUTRO";
   if(g_scoreAtual >= LimiarCompra)
      direcao = "COMPRA";
   else
      if(g_scoreAtual <= -LimiarVenda)
         direcao = "VENDA";

   string texto = "";

   texto += "==============================================\n";
   texto += "  MESA - Mesa de Operacoes Algoritmica (MT4)\n";
   texto += "==============================================\n";
   texto += StringFormat(" Simbolo: %-10s  TF: %-6s  Magic: %d\n",
                         Symbol(), TimeframeToText(g_timeframe), MagicNumber);
   texto += StringFormat(" Servidor: %s\n", TimeToString(agora, TIME_DATE | TIME_SECONDS));
   texto += "----------------------------------------------\n";

   //--- bloco de sinal
   texto += StringFormat(" SCORE: %+7.2f   ->  %s\n", g_scoreAtual, direcao);
   texto += StringFormat("   Limiares: compra >= %+.1f | venda <= %+.1f\n", LimiarCompra, -LimiarVenda);
   texto += StringFormat("   EMA %+.2f | RSI %+.2f | MACD %+.2f\n",
                         g_breakdown.ema, g_breakdown.rsi, g_breakdown.macd);
   texto += StringFormat("   BB  %+.2f | ADX %+.2f | ATR  %+.2f\n",
                         g_breakdown.bollinger, g_breakdown.adx, g_breakdown.atr);
   texto += "----------------------------------------------\n";

   //--- leituras dos indicadores
   texto += " INDICADORES\n";
   texto += StringFormat("   EMA%-3d %s   EMA%-3d %s\n",
                         EmaRapidaPeriodo, DoubleToString(snap.emaRapida, g_digits),
                         EmaLentaPeriodo,  DoubleToString(snap.emaLenta,  g_digits));
   texto += StringFormat("   RSI(%d) %.2f   ADX(%d) %.2f  (+DI %.1f / -DI %.1f)\n",
                         RsiPeriodo, snap.rsi, AdxPeriodo, snap.adx, snap.adxMais, snap.adxMenos);
   texto += StringFormat("   MACD %.5f  Sinal %.5f  Hist %.5f\n",
                         snap.macdPrincipal, snap.macdSinal, snap.macdPrincipal - snap.macdSinal);
   texto += StringFormat("   ATR %s (%.1f pips)\n",
                         DoubleToString(snap.atr, g_digits), PriceToPips(snap.atr));
   texto += StringFormat("   BB  Sup %s | Med %s | Inf %s\n",
                         DoubleToString(snap.bbSuperior, g_digits),
                         DoubleToString(snap.bbMedia,    g_digits),
                         DoubleToString(snap.bbInferior, g_digits));
   texto += "----------------------------------------------\n";

   //--- filtros
   texto += " FILTROS\n";
   texto += StringFormat("   Ano .............. %s\n", StatusLabel(okAno));
   texto += StringFormat("   Mes .............. %s\n", StatusLabel(okMes));
   texto += StringFormat("   Dia do mes ....... %s\n", StatusLabel(okDiaMes));
   texto += StringFormat("   Dia da semana .... %s (%s)\n", StatusLabel(okSemana), WeekdayName(TimeDayOfWeek(agora)));
   texto += StringFormat("   Blackout ......... %s\n", StatusLabel(okBlack));
   texto += StringFormat("   Janela horario ... %s (%02d:%02d-%02d:%02d)\n",
                         StatusLabel(okHora), HoraInicio, MinutoInicio, HoraFim, MinutoFim);
   texto += StringFormat("   Sessao ........... %s (%s)\n", StatusLabel(okSessao), sessao);
   texto += StringFormat("   Spread ........... %s (%.1f pts)%s\n", StatusLabel(okSpread), spread,
                         (okSpread ? "" : " - " + motivoSpread));
   texto += StringFormat("   Indicadores ...... %s%s\n", StatusLabel(okGates),
                         (okGates ? "" : " - " + motivoGate));
   texto += StringFormat("   Posicoes max ..... %s (%d/%d)\n", StatusLabel(okPosicoes), posicoes, MaxPosicoesSimultaneas);
   texto += StringFormat("   Trades/dia ....... %s (%d/%d)\n", StatusLabel(okTrades), tradesHoje, MaxTradesPorDia);
   texto += StringFormat("   Limite diario .... %s%s\n", StatusLabel(okDiario),
                         (okDiario ? "" : " - " + g_motivoLimite));
   texto += "----------------------------------------------\n";

   //--- resultado do dia
   texto += " RESULTADO DO DIA\n";
   texto += StringFormat("   PnL: %+.2f (%+.2f%%) | Saldo inicial: %.2f\n",
                         pnlDia, pnlDiaPct, g_saldoInicioDia);
   texto += StringFormat("   Saldo: %.2f | Equity: %.2f | Margem livre: %.2f\n",
                         AccountBalance(), AccountEquity(), AccountFreeMargin());
   texto += "----------------------------------------------\n";

   //--- status geral
   texto += StringFormat(" STATUS: %s\n", (g_permitidoAgora ? "OPERACAO LIBERADA" : "OPERACAO BLOQUEADA"));
   if(!g_permitidoAgora && StringLen(g_motivoBloqueio) > 0)
      texto += StringFormat(" MOTIVO: %s\n", g_motivoBloqueio);
   if(StringLen(g_ultimaMensagem) > 0)
      texto += StringFormat(" LOG: %s\n", g_ultimaMensagem);
   texto += "==============================================";

   Comment(texto);
  }

//+------------------------------------------------------------------+
//| Converte o codigo de timeframe do MQL4 em texto legivel.          |
//+------------------------------------------------------------------+
string TimeframeToText(const int tf)
  {
   switch(tf)
     {
      case 1:     return("M1");
      case 5:     return("M5");
      case 15:    return("M15");
      case 30:    return("M30");
      case 60:    return("H1");
      case 240:   return("H4");
      case 1440:  return("D1");
      case 10080: return("W1");
      case 43200: return("MN1");
     }
   return(StringFormat("%d", tf));
  }

//==================================================================//
//  S13 - HANDLERS DE EVENTO                                        //
//==================================================================//

//+------------------------------------------------------------------+
//| OnInit - validacao dos parametros e preparo do contexto.          |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- contexto do simbolo
   g_digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   g_point  = MarketInfo(Symbol(), MODE_POINT);

   if(g_point <= 0.0)
      g_point = Point;
   if(g_digits <= 0)
      g_digits = Digits;

   //--- ajuste para corretoras de 3 e 5 digitos
   g_pipMultiplier = 1;
   if(g_digits == 3 || g_digits == 5)
      g_pipMultiplier = 10;
   g_pipSize = g_point * g_pipMultiplier;

   //--- slippage informado em pips convertido para pontos
   g_slippagePontos = (int)MathRound(DesvioMaximoPips * g_pipMultiplier);
   if(g_slippagePontos < 0)
      g_slippagePontos = 0;

   //--- timeframe efetivo
   g_timeframe = (TimeframeAnalise <= 0 ? Period() : TimeframeAnalise);

   //--- validacoes de parametros
   if(EmaRapidaPeriodo <= 0 || EmaLentaPeriodo <= 0)
     {
      Print("[MESA] Periodos de EMA invalidos.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(EmaRapidaPeriodo >= EmaLentaPeriodo)
      Print("[MESA] Aviso: a EMA rapida nao e menor que a EMA lenta.");

   if(RsiPeriodo <= 0 || AtrPeriodo <= 0 || BollingerPeriodo <= 0 || AdxPeriodo <= 0)
     {
      Print("[MESA] Periodos de indicador invalidos.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(MacdRapida <= 0 || MacdLenta <= 0 || MacdSinal <= 0)
     {
      Print("[MESA] Periodos do MACD invalidos.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   double somaPesos = PesoEma + PesoRsi + PesoMacd + PesoBollinger + PesoAdx + PesoAtr;
   if(somaPesos <= 0.0)
     {
      Print("[MESA] A soma dos pesos dos indicadores deve ser maior que zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(LimiarCompra < 0.0 || LimiarCompra > 100.0 || LimiarVenda < 0.0 || LimiarVenda > 100.0)
     {
      Print("[MESA] Limiares de entrada devem estar entre 0 e 100.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(HoraInicio < 0 || HoraInicio > 23 || HoraFim < 0 || HoraFim > 23 ||
      MinutoInicio < 0 || MinutoInicio > 59 || MinutoFim < 0 || MinutoFim > 59)
     {
      Print("[MESA] Janela de horario invalida.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(UsarFiltroAno && AnoMinimo > AnoMaximo)
     {
      Print("[MESA] AnoMinimo nao pode ser maior que AnoMaximo.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(ModoVolume == VOLUME_LOTE_FIXO && LoteFixo <= 0.0)
     {
      Print("[MESA] LoteFixo deve ser maior que zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(ModoVolume == VOLUME_RISCO_PCT && RiscoPorTradePct <= 0.0)
     {
      Print("[MESA] RiscoPorTradePct deve ser maior que zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   //--- estado inicial
   g_ultimaBarra          = 0;
   g_diaCorrente          = 0;
   g_saldoInicioDia       = AccountBalance();
   g_limiteDiarioAtingido = false;
   g_motivoLimite         = "";
   g_scoreAtual           = 0.0;
   g_motivoBloqueio       = "";
   g_permitidoAgora       = true;
   g_ultimaMensagem       = "";

   g_breakdown.ema       = 0.0;
   g_breakdown.rsi       = 0.0;
   g_breakdown.macd      = 0.0;
   g_breakdown.bollinger = 0.0;
   g_breakdown.adx       = 0.0;
   g_breakdown.atr       = 0.0;
   g_breakdown.somaPesos = 0.0;
   g_breakdown.total     = 0.0;

   UpdateDailyContext();

   Print(StringFormat("[MESA] Inicializado em %s | Digits=%d Point=%s pipMultiplier=%d TF=%s",
                      Symbol(), g_digits, DoubleToString(g_point, 8), g_pipMultiplier,
                      TimeframeToText(g_timeframe)));

   if(!IsTradeAllowed())
      Print("[MESA] Aviso: negociacao automatica desabilitada no terminal.");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit - limpeza do painel.                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
   Print(StringFormat("[MESA] Finalizado. Motivo=%d", reason));
  }

//+------------------------------------------------------------------+
//| OnTick - ciclo principal.                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1) contexto diario (reinicia contadores na virada do dia)
   UpdateDailyContext();

   //--- 2) leitura dos indicadores (usada pelo painel e pelo sinal)
   IndicatorSnapshot snap;
   ReadIndicators(snap);

   //--- 3) score ponderado
   g_scoreAtual = ComputeScore(snap, g_breakdown);

   //--- 4) gestao de posicoes abertas (a cada tick)
   ManageOpenPositions();

   //--- 5) fechamentos programados
   CheckAutoClose();

   //--- 6) avaliacao dos filtros para exibicao e decisao
   datetime agora = TimeCurrent();
   string motivo = "";
   g_permitidoAgora = IsTradingAllowed(agora, motivo);
   g_motivoBloqueio = motivo;

   //--- 7) painel
   UpdatePanel(snap);

   //--- 8) execucao apenas no fechamento de nova barra
   bool novaBarra = IsNewBar();
   if(OperarSomenteNovaBarra && !novaBarra)
      return;

   //--- 9) pre-requisitos de execucao ------------------------------
   if(!IsTradeAllowed())
     {
      g_motivoBloqueio = "Negociacao automatica desabilitada no terminal";
      g_permitidoAgora = false;
      return;
     }

   if(!snap.valido)
     {
      g_motivoBloqueio = "Historico/indicadores insuficientes";
      g_permitidoAgora = false;
      return;
     }

   if(!g_permitidoAgora)
      return;

   //--- limites diarios
   if(!CheckDailyLimits())
     {
      g_permitidoAgora = false;
      g_motivoBloqueio = g_motivoLimite;
      return;
     }

   //--- filtro de spread
   string motivoSpread = "";
   if(!PassesSpreadFilter(motivoSpread))
     {
      g_permitidoAgora = false;
      g_motivoBloqueio = motivoSpread;
      return;
     }

   //--- filtros duros de indicador (ADX / ATR)
   string motivoGate = "";
   if(!PassesIndicatorGates(snap, motivoGate))
     {
      g_permitidoAgora = false;
      g_motivoBloqueio = motivoGate;
      return;
     }

   //--- limite de posicoes simultaneas
   int posicoes = CountOpenPositions();
   if(MaxPosicoesSimultaneas > 0 && posicoes >= MaxPosicoesSimultaneas)
     {
      g_motivoBloqueio = StringFormat("Limite de posicoes simultaneas atingido (%d)", posicoes);
      return;
     }

   //--- limite de trades por dia
   int tradesHoje = CountTradesToday();
   if(MaxTradesPorDia > 0 && tradesHoje >= MaxTradesPorDia)
     {
      g_motivoBloqueio = StringFormat("Limite de trades diarios atingido (%d)", tradesHoje);
      return;
     }

   //--- 10) decisao de entrada -------------------------------------
   int sinal = SINAL_NEUTRO;

   if(g_scoreAtual >= LimiarCompra)
      sinal = SINAL_COMPRA;
   else
      if(g_scoreAtual <= -LimiarVenda)
         sinal = SINAL_VENDA;

   if(sinal == SINAL_NEUTRO)
      return;

   if(sinal == SINAL_COMPRA && !PermitirCompras)
     {
      g_motivoBloqueio = "Compras desabilitadas nos parametros";
      return;
     }

   if(sinal == SINAL_VENDA && !PermitirVendas)
     {
      g_motivoBloqueio = "Vendas desabilitadas nos parametros";
      return;
     }

   //--- evita duplicar posicao na mesma direcao
   int cmd = (sinal == SINAL_COMPRA ? OP_BUY : OP_SELL);
   if(CountOpenPositionsByType(cmd) > 0)
     {
      g_motivoBloqueio = "Ja existe posicao aberta nesta direcao";
      return;
     }

   //--- 11) execucao ------------------------------------------------
   LogInfo(StringFormat("Sinal %s detectado. Score=%.2f",
                        (sinal == SINAL_COMPRA ? "COMPRA" : "VENDA"), g_scoreAtual));

   ExecuteEntry(cmd, snap);
  }
//+------------------------------------------------------------------+
