//+------------------------------------------------------------------+
//|                                                       MesaEA.mq5 |
//|                          MESA - Mesa de Operacoes Algoritmica    |
//|                                              MESA Trading Desk   |
//+------------------------------------------------------------------+
#property copyright "MESA Trading Desk"
#property link      "https://mesa.trading"
#property version   "1.00"
#property strict
#property description "MESA - Robo-base da Mesa de Operacoes Algoritmica."
#property description "Motor de sinal ponderado (EMA/RSI/MACD/ATR/Bollinger/ADX),"
#property description "bateria completa de filtros de tempo e gestao de risco por capital."

//==================================================================//
//  INCLUDES - somente biblioteca padrao da MetaTrader 5            //
//==================================================================//
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================//
//  ENUMERACOES DE CONFIGURACAO                                     //
//==================================================================//

//--- Criterio de dimensionamento do lote
enum ENUM_MESA_LOT_MODE
  {
   MESA_LOT_FIXED = 0,   // Lote fixo
   MESA_LOT_RISK  = 1    // Risco % do saldo
  };

//--- Criterio de calculo de stop loss / take profit
enum ENUM_MESA_STOP_MODE
  {
   MESA_STOP_ATR    = 0, // Multiplo de ATR
   MESA_STOP_POINTS = 1  // Pontos fixos
  };

//--- Criterio de trailing stop
enum ENUM_MESA_TRAIL_MODE
  {
   MESA_TRAIL_OFF    = 0, // Desligado
   MESA_TRAIL_ATR    = 1, // Multiplo de ATR
   MESA_TRAIL_POINTS = 2  // Pontos fixos
  };

//--- Interpretacao do RSI dentro do motor de sinal
enum ENUM_MESA_RSI_MODE
  {
   MESA_RSI_TREND     = 0, // Tendencia (acima/abaixo de 50)
   MESA_RSI_REVERSION = 1  // Reversao (extremos sobrecompra/sobrevenda)
  };

//==================================================================//
//  PARAMETROS DE ENTRADA                                           //
//==================================================================//

input group "=== 1. Identificacao e Execucao ==="
input long              MagicNumber              = 20260719;    // Magic number da mesa
input string            ComentarioOrdem          = "MESA";      // Comentario anexado a ordem
input ENUM_TIMEFRAMES   TimeframeAnalise         = PERIOD_CURRENT; // Timeframe de analise
input int               DesvioMaximoPontos       = 20;          // Desvio maximo (slippage) em pontos
input bool              OperarSomenteNovaBarra   = true;        // Avaliar sinal somente no fechamento da barra
input bool              LogDetalhado             = true;        // Gravar log detalhado no Experts

input group "=== 2. Indicadores ==="
input int               EmaRapidaPeriodo         = 9;           // EMA rapida - periodo
input int               EmaLentaPeriodo          = 21;          // EMA lenta - periodo
input int               RsiPeriodo               = 14;          // RSI - periodo
input int               RsiNivelSobrecompra      = 70;          // RSI - nivel de sobrecompra
input int               RsiNivelSobrevenda       = 30;          // RSI - nivel de sobrevenda
input ENUM_MESA_RSI_MODE RsiModo                 = MESA_RSI_TREND; // RSI - modo de leitura
input int               MacdRapida               = 12;          // MACD - EMA rapida
input int               MacdLenta                = 26;          // MACD - EMA lenta
input int               MacdSinal                = 9;           // MACD - periodo do sinal
input int               AtrPeriodo               = 14;          // ATR - periodo
input int               BollingerPeriodo         = 20;          // Bollinger - periodo
input double            BollingerDesvio          = 2.0;         // Bollinger - desvio padrao
input int               AdxPeriodo               = 14;          // ADX - periodo
input double            AdxMinimo                = 20.0;        // ADX minimo para permitir entrada
input bool              UsarFiltroVolatilidade   = true;        // Usar filtro de volatilidade por ATR
input double            AtrMinimoPontos          = 0.0;         // ATR minimo em pontos (0 = ignora)
input double            AtrMaximoPontos          = 0.0;         // ATR maximo em pontos (0 = ignora)

input group "=== 3. Motor de Sinal (Pesos) ==="
input double            PesoEma                  = 30.0;        // Peso do cruzamento de EMAs
input double            PesoRsi                  = 15.0;        // Peso do RSI
input double            PesoMacd                 = 25.0;        // Peso do MACD
input double            PesoBollinger            = 15.0;        // Peso das Bandas de Bollinger
input double            PesoAdx                  = 15.0;        // Peso do direcional ADX (+DI/-DI)
input double            LimiarCompra             = 45.0;        // Score minimo para comprar (0..100)
input double            LimiarVenda              = 45.0;        // Score minimo (modulo) para vender (0..100)

input group "=== 4. Filtro de Horario ==="
input bool              UsarFiltroHorario        = true;        // Ativar janela de negociacao
input int               HoraInicio               = 9;           // Hora de inicio (0-23, hora do servidor)
input int               MinutoInicio             = 0;           // Minuto de inicio (0-59)
input int               HoraFim                  = 17;          // Hora de fim (0-23, hora do servidor)
input int               MinutoFim                = 30;          // Minuto de fim (0-59)

input group "=== 5. Filtro de Dias da Semana ==="
input bool              OperarSegunda            = true;        // Negociar na segunda-feira
input bool              OperarTerca              = true;        // Negociar na terca-feira
input bool              OperarQuarta             = true;        // Negociar na quarta-feira
input bool              OperarQuinta             = true;        // Negociar na quinta-feira
input bool              OperarSexta              = true;        // Negociar na sexta-feira
input bool              OperarSabado             = false;       // Negociar no sabado
input bool              OperarDomingo            = false;       // Negociar no domingo

input group "=== 6. Filtro de Calendario (Dia/Mes/Ano) ==="
input bool              UsarFiltroDiaDoMes       = false;       // Ativar filtro de dia do mes
input string            DiasDoMesPermitidos      = "1-31";      // Dias permitidos, ex: "1,2,15-20,31"
input bool              UsarFiltroMes            = false;       // Ativar filtro de mes
input string            MesesPermitidos          = "1-12";      // Meses permitidos, ex: "1-6,9,10-12"
input bool              UsarFiltroAno            = false;       // Ativar filtro de ano
input int               AnoMinimo                = 2020;        // Ano minimo permitido
input int               AnoMaximo                = 2099;        // Ano maximo permitido

input group "=== 7. Filtro de Blackout (Datas Proibidas) ==="
input bool              UsarBlackout             = false;       // Ativar lista de datas proibidas
input string            DatasBlackout            = "";          // Datas AAAA.MM.DD separadas por virgula

input group "=== 8. Filtro de Sessoes ==="
input bool              UsarFiltroSessao         = false;       // Ativar filtro de sessoes
input int               OffsetGmtServidor        = 3;           // Offset GMT do servidor (horas, ex: +3)
input bool              SessaoAsia               = false;       // Operar na sessao da Asia
input int               AsiaInicioGmt            = 0;           // Asia - hora inicial GMT
input int               AsiaFimGmt               = 8;           // Asia - hora final GMT
input bool              SessaoLondres            = true;        // Operar na sessao de Londres
input int               LondresInicioGmt         = 7;           // Londres - hora inicial GMT
input int               LondresFimGmt            = 16;          // Londres - hora final GMT
input bool              SessaoNovaYork           = true;        // Operar na sessao de Nova York
input int               NovaYorkInicioGmt        = 12;          // Nova York - hora inicial GMT
input int               NovaYorkFimGmt           = 21;          // Nova York - hora final GMT

input group "=== 9. Gestao de Risco e Lote ==="
input ENUM_MESA_LOT_MODE ModoLote                = MESA_LOT_RISK; // Criterio de dimensionamento
input double            LoteFixo                 = 0.10;        // Lote fixo (quando aplicavel)
input double            RiscoPorTradePct         = 1.0;         // Risco por trade (% do saldo)
input double            LoteMaximoPermitido      = 5.0;         // Teto absoluto de lote
input int               SpreadMaximoPontos       = 30;          // Spread maximo aceito (pontos)

input group "=== 10. Stops, Alvos e Trailing ==="
input ENUM_MESA_STOP_MODE ModoStop               = MESA_STOP_ATR; // Criterio de stop/alvo
input double            AtrMultiploStop          = 2.0;         // Stop = ATR x multiplo
input double            AtrMultiploAlvo          = 3.0;         // Alvo = ATR x multiplo
input int               StopPontos               = 300;         // Stop em pontos (modo pontos)
input int               AlvoPontos               = 600;         // Alvo em pontos (modo pontos)
input bool              UsarBreakEven            = true;        // Ativar break-even automatico
input double            BreakEvenGatilhoAtr      = 1.0;         // Gatilho do break-even (x ATR)
input int               BreakEvenGatilhoPontos   = 200;         // Gatilho do break-even (pontos)
input int               BreakEvenOffsetPontos    = 10;          // Offset travado acima do preco de entrada
input ENUM_MESA_TRAIL_MODE ModoTrailing          = MESA_TRAIL_ATR; // Criterio de trailing stop
input double            TrailingAtrMultiplo      = 1.5;         // Trailing = ATR x multiplo
input int               TrailingPontos           = 250;         // Trailing em pontos
input int               TrailingPassoPontos      = 10;          // Passo minimo para mover o stop

input group "=== 11. Limites Diarios e Exposicao ==="
input bool              UsarLimitePerdaDiaria    = true;        // Ativar limite de perda diaria
input double            PerdaDiariaMaximaPct     = 3.0;         // Perda diaria maxima (% do saldo inicial do dia)
input bool              UsarMetaGanhoDiario      = true;        // Ativar meta de ganho diario
input double            MetaGanhoDiarioPct       = 5.0;         // Meta de ganho diario (%)
input bool              IncluirFlutuanteNoLimite = true;        // Somar resultado flutuante aos limites
input int               MaxPosicoesSimultaneas   = 1;           // Maximo de posicoes simultaneas
input int               MaxTradesPorDia          = 10;          // Maximo de trades por dia (0 = sem limite)
input bool              PermitirPosicoesOpostas  = false;       // Permitir compra e venda ao mesmo tempo

input group "=== 12. Encerramento e Painel ==="
input bool              FecharTudoNoFimDaJanela  = false;       // Encerrar posicoes ao sair da janela
input bool              FecharTudoNaSexta        = false;       // Encerrar posicoes na sexta-feira
input int               HoraFechamentoSexta      = 20;          // Hora do encerramento de sexta (servidor)
input bool              MostrarPainel            = true;        // Exibir painel on-chart
input int               PainelIntervaloMs        = 1000;        // Intervalo de atualizacao do painel (ms)

//==================================================================//
//  ESTRUTURAS DE DADOS                                             //
//==================================================================//

//------------------------------------------------------------------
// IndicatorSnapshot
// Fotografia completa dos indicadores em dois instantes:
//   - "Now"  = ultima barra FECHADA  (shift 1)
//   - "Prev" = barra anterior a ela  (shift 2)
// Trabalhar com barras fechadas evita repintura de sinal.
//------------------------------------------------------------------
struct IndicatorSnapshot
  {
   bool     valid;          // leitura integra de todos os buffers
   datetime barTime;        // horario de abertura da barra de referencia

   double   closeNow;       // fechamento da barra de referencia
   double   closePrev;      // fechamento da barra anterior

   double   emaFastNow;     // EMA rapida
   double   emaFastPrev;
   double   emaSlowNow;     // EMA lenta
   double   emaSlowPrev;

   double   rsiNow;         // RSI
   double   rsiPrev;

   double   macdMainNow;    // MACD linha principal
   double   macdMainPrev;
   double   macdSignalNow;  // MACD linha de sinal
   double   macdSignalPrev;
   double   macdHistNow;    // Histograma = principal - sinal
   double   macdHistPrev;

   double   atrNow;         // ATR (volatilidade)
   double   atrPrev;

   double   bbUpperNow;     // Bollinger banda superior
   double   bbMiddleNow;    // Bollinger banda central
   double   bbLowerNow;     // Bollinger banda inferior
   double   bbUpperPrev;
   double   bbLowerPrev;

   double   adxNow;         // ADX principal (forca)
   double   adxPrev;
   double   plusDiNow;      // +DI
   double   minusDiNow;     // -DI
  };

//------------------------------------------------------------------
// FilterStatus
// Estado individual de cada filtro, preservado para o painel/log.
//------------------------------------------------------------------
struct FilterStatus
  {
   bool     terminalOk;     // contexto de trading do terminal/conta
   bool     spreadOk;       // spread dentro do teto
   bool     hourOk;         // janela de horario
   bool     weekdayOk;      // dia da semana
   bool     dayOfMonthOk;   // dia do mes
   bool     monthOk;        // mes
   bool     yearOk;         // ano
   bool     blackoutOk;     // fora de data proibida
   bool     sessionOk;      // sessao permitida
   bool     dailyLossOk;    // limite de perda diaria
   bool     dailyGoalOk;    // meta de ganho diario
   bool     tradeCountOk;   // limite de trades no dia
   bool     exposureOk;     // limite de posicoes simultaneas
   bool     volatilityOk;   // filtro de volatilidade (ATR)
   string   reason;         // motivo do bloqueio (ou "LIBERADO")
  };

//==================================================================//
//  OBJETOS E VARIAVEIS GLOBAIS                                     //
//==================================================================//

CTrade         g_trade;         // executor de ordens
CPositionInfo  g_position;      // leitor de posicoes
CSymbolInfo    g_symbol;        // leitor de propriedades do simbolo

//--- Handles dos indicadores
int            g_hEmaFast   = INVALID_HANDLE;
int            g_hEmaSlow   = INVALID_HANDLE;
int            g_hRsi       = INVALID_HANDLE;
int            g_hMacd      = INVALID_HANDLE;
int            g_hAtr       = INVALID_HANDLE;
int            g_hBands     = INVALID_HANDLE;
int            g_hAdx       = INVALID_HANDLE;

//--- Contexto de execucao
ENUM_TIMEFRAMES g_timeframe  = PERIOD_CURRENT;
datetime        g_lastBarTime = 0;
bool            g_wasInsideWindow = false;
uint            g_lastPanelTick = 0;

//--- Caixa do dia (recalculada a partir do historico, resiste a restart)
datetime        g_dayStart        = 0;
double          g_dayRealizedPnL  = 0.0;
double          g_dayFloatingPnL  = 0.0;
double          g_dayStartBalance = 0.0;
int             g_dayTradeCount   = 0;

//--- Ultimo estado conhecido, usado pelo painel
IndicatorSnapshot g_snapshot;
FilterStatus      g_filters;
double            g_lastScore = 0.0;

//==================================================================//
//  SECAO 1 - CICLO DE VIDA DO EXPERT                               //
//==================================================================//

//+------------------------------------------------------------------+
//| OnInit - valida parametros, cria handles e prepara o executor    |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Resolve o timeframe efetivo de analise
   g_timeframe = (TimeframeAnalise == PERIOD_CURRENT) ? Period() : TimeframeAnalise;

   //--- Critica dos parametros antes de qualquer alocacao
   string validationError = "";
   if(!ValidateInputs(validationError))
     {
      Print("[MESA] Parametros invalidos: ", validationError);
      return(INIT_PARAMETERS_INCORRECT);
     }

   //--- Prepara o leitor de simbolo
   if(!g_symbol.Name(_Symbol))
     {
      Print("[MESA] Falha ao selecionar o simbolo ", _Symbol);
      return(INIT_FAILED);
     }
   g_symbol.Refresh();
   g_symbol.RefreshRates();

   //--- Configura o executor de ordens
   g_trade.SetExpertMagicNumber((ulong)MagicNumber);
   g_trade.SetDeviationInPoints((ulong)DesvioMaximoPontos);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);

   //--- Cria os handles dos indicadores
   if(!CreateIndicatorHandles())
     {
      Print("[MESA] Falha ao criar um ou mais handles de indicador. Erro: ", _LastError);
      ReleaseIndicatorHandles();
      return(INIT_FAILED);
     }

   //--- Zera o estado
   ZeroMemory(g_snapshot);
   ResetFilterStatus(g_filters);
   g_lastBarTime = 0;
   g_lastScore   = 0.0;
   g_dayStart    = 0;

   UpdateDailyStats();

   PrintFormat("[MESA] Inicializado em %s / %s | Magic %I64d | Modo lote: %s",
               _Symbol, EnumToString(g_timeframe), MagicNumber,
               (ModoLote == MESA_LOT_RISK ? "risco %" : "lote fixo"));

   if(MostrarPainel)
      DrawPanel();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit - libera handles e limpa o grafico                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ReleaseIndicatorHandles();
   Comment("");
   ChartRedraw();
   PrintFormat("[MESA] Finalizado. Motivo do encerramento: %d", reason);
  }

//+------------------------------------------------------------------+
//| OnTick - orquestra gestao de posicoes e geracao de sinal         |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Cotacoes atualizadas sao pre-requisito de tudo
   if(!g_symbol.RefreshRates())
      return;

   //--- Caixa do dia (PnL realizado, flutuante e contagem de trades)
   UpdateDailyStats();

   //--- Gestao das posicoes abertas roda a cada tick (break-even/trailing)
   ManageOpenPositions();

   //--- Encerramentos programados (fim de janela / sexta-feira)
   HandleScheduledClosures();

   //--- Atualizacao do painel com throttle para nao pesar o grafico
   RefreshPanelState();

   //--- Entradas somente no fechamento de uma nova barra
   if(OperarSomenteNovaBarra && !IsNewBar())
      return;

   ProcessSignal();
  }

//==================================================================//
//  SECAO 2 - INDICADORES                                           //
//==================================================================//

//+------------------------------------------------------------------+
//| CreateIndicatorHandles - instancia todos os indicadores          |
//+------------------------------------------------------------------+
bool CreateIndicatorHandles()
  {
   g_hEmaFast = iMA(_Symbol, g_timeframe, EmaRapidaPeriodo, 0, MODE_EMA, PRICE_CLOSE);
   g_hEmaSlow = iMA(_Symbol, g_timeframe, EmaLentaPeriodo,  0, MODE_EMA, PRICE_CLOSE);
   g_hRsi     = iRSI(_Symbol, g_timeframe, RsiPeriodo, PRICE_CLOSE);
   g_hMacd    = iMACD(_Symbol, g_timeframe, MacdRapida, MacdLenta, MacdSinal, PRICE_CLOSE);
   g_hAtr     = iATR(_Symbol, g_timeframe, AtrPeriodo);
   g_hBands   = iBands(_Symbol, g_timeframe, BollingerPeriodo, 0, BollingerDesvio, PRICE_CLOSE);
   g_hAdx     = iADX(_Symbol, g_timeframe, AdxPeriodo);

   if(g_hEmaFast == INVALID_HANDLE || g_hEmaSlow == INVALID_HANDLE ||
      g_hRsi     == INVALID_HANDLE || g_hMacd    == INVALID_HANDLE ||
      g_hAtr     == INVALID_HANDLE || g_hBands   == INVALID_HANDLE ||
      g_hAdx     == INVALID_HANDLE)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| ReleaseIndicatorHandles - devolve os handles ao terminal         |
//+------------------------------------------------------------------+
void ReleaseIndicatorHandles()
  {
   if(g_hEmaFast != INVALID_HANDLE) { IndicatorRelease(g_hEmaFast); g_hEmaFast = INVALID_HANDLE; }
   if(g_hEmaSlow != INVALID_HANDLE) { IndicatorRelease(g_hEmaSlow); g_hEmaSlow = INVALID_HANDLE; }
   if(g_hRsi     != INVALID_HANDLE) { IndicatorRelease(g_hRsi);     g_hRsi     = INVALID_HANDLE; }
   if(g_hMacd    != INVALID_HANDLE) { IndicatorRelease(g_hMacd);    g_hMacd    = INVALID_HANDLE; }
   if(g_hAtr     != INVALID_HANDLE) { IndicatorRelease(g_hAtr);     g_hAtr     = INVALID_HANDLE; }
   if(g_hBands   != INVALID_HANDLE) { IndicatorRelease(g_hBands);   g_hBands   = INVALID_HANDLE; }
   if(g_hAdx     != INVALID_HANDLE) { IndicatorRelease(g_hAdx);     g_hAdx     = INVALID_HANDLE; }
  }

//+------------------------------------------------------------------+
//| CopyIndicatorValues - le "count" valores de um buffer            |
//| Retorna false se a serie ainda nao estiver calculada.            |
//+------------------------------------------------------------------+
bool CopyIndicatorValues(const int handle, const int bufferIndex, const int count, double &out[])
  {
   ArraySetAsSeries(out, true);
   int copied = CopyBuffer(handle, bufferIndex, 0, count, out);
   if(copied < count)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| ReadIndicators - preenche a struct IndicatorSnapshot             |
//|                                                                  |
//| Le 3 valores de cada buffer (indices 0,1,2 em serie temporal) e  |
//| trabalha com a barra 1 como "Now" e a barra 2 como "Prev",       |
//| garantindo que apenas barras FECHADAS alimentem o motor.         |
//+------------------------------------------------------------------+
bool ReadIndicators(IndicatorSnapshot &s)
  {
   ZeroMemory(s);
   s.valid = false;

   const int need = 3;   // 0 = barra em formacao, 1 = fechada, 2 = anterior

   double emaFast[], emaSlow[], rsi[], macdMain[], macdSig[];
   double atr[], bbUp[], bbMid[], bbLow[], adx[], plusDi[], minusDi[];
   double closes[];

   if(!CopyIndicatorValues(g_hEmaFast, 0, need, emaFast)) return(false);
   if(!CopyIndicatorValues(g_hEmaSlow, 0, need, emaSlow)) return(false);
   if(!CopyIndicatorValues(g_hRsi,     0, need, rsi))     return(false);
   if(!CopyIndicatorValues(g_hMacd,    0, need, macdMain))return(false);
   if(!CopyIndicatorValues(g_hMacd,    1, need, macdSig)) return(false);
   if(!CopyIndicatorValues(g_hAtr,     0, need, atr))     return(false);
   if(!CopyIndicatorValues(g_hBands,   1, need, bbUp))    return(false);
   if(!CopyIndicatorValues(g_hBands,   0, need, bbMid))   return(false);
   if(!CopyIndicatorValues(g_hBands,   2, need, bbLow))   return(false);
   if(!CopyIndicatorValues(g_hAdx,     0, need, adx))     return(false);
   if(!CopyIndicatorValues(g_hAdx,     1, need, plusDi))  return(false);
   if(!CopyIndicatorValues(g_hAdx,     2, need, minusDi)) return(false);

   ArraySetAsSeries(closes, true);
   if(CopyClose(_Symbol, g_timeframe, 0, need, closes) < need)
      return(false);

   //--- Preco
   s.closeNow  = closes[1];
   s.closePrev = closes[2];

   //--- Medias exponenciais
   s.emaFastNow  = emaFast[1];
   s.emaFastPrev = emaFast[2];
   s.emaSlowNow  = emaSlow[1];
   s.emaSlowPrev = emaSlow[2];

   //--- RSI
   s.rsiNow  = rsi[1];
   s.rsiPrev = rsi[2];

   //--- MACD (o iMACD da MT5 expoe principal e sinal; histograma e derivado)
   s.macdMainNow    = macdMain[1];
   s.macdMainPrev   = macdMain[2];
   s.macdSignalNow  = macdSig[1];
   s.macdSignalPrev = macdSig[2];
   s.macdHistNow    = macdMain[1] - macdSig[1];
   s.macdHistPrev   = macdMain[2] - macdSig[2];

   //--- ATR
   s.atrNow  = atr[1];
   s.atrPrev = atr[2];

   //--- Bandas de Bollinger
   s.bbUpperNow  = bbUp[1];
   s.bbMiddleNow = bbMid[1];
   s.bbLowerNow  = bbLow[1];
   s.bbUpperPrev = bbUp[2];
   s.bbLowerPrev = bbLow[2];

   //--- ADX e direcionais
   s.adxNow     = adx[1];
   s.adxPrev    = adx[2];
   s.plusDiNow  = plusDi[1];
   s.minusDiNow = minusDi[1];

   s.barTime = iTime(_Symbol, g_timeframe, 1);
   s.valid   = true;

   return(true);
  }

//==================================================================//
//  SECAO 3 - MOTOR DE SINAL PONDERADO                              //
//==================================================================//

//+------------------------------------------------------------------+
//| ComputeScore - converte a leitura tecnica em um score -100..+100 |
//|                                                                  |
//| Metodo:                                                          |
//|   1. Cada indicador produz um sinal normalizado em [-1, +1],     |
//|      onde +1 e maxima conviccao compradora e -1 vendedora.       |
//|   2. Cada sinal e multiplicado pelo seu peso configuravel.       |
//|   3. O somatorio e dividido pela soma dos pesos ativos e         |
//|      escalado para a faixa -100..+100.                           |
//|                                                                  |
//| Contribuicoes:                                                   |
//|   EMA       - cruzamento vale +/-1.0; simples alinhamento +/-0.5 |
//|   RSI       - modo tendencia (distancia de 50) ou modo reversao  |
//|               (extremos de sobrecompra/sobrevenda)               |
//|   MACD      - lado do histograma e sua aceleracao                |
//|   Bollinger - posicao relativa do preco no envelope              |
//|   ADX       - direcao por +DI/-DI ponderada pela forca do ADX    |
//|                                                                  |
//| O ATR nao pontua: atua como filtro de volatilidade e insumo de   |
//| dimensionamento de stops, conforme boa pratica de risco.         |
//+------------------------------------------------------------------+
double ComputeScore(const IndicatorSnapshot &s)
  {
   if(!s.valid)
      return(0.0);

   double weightedSum = 0.0;
   double weightTotal = 0.0;

   //---------------------------------------------------------------
   // 1) EMA rapida x EMA lenta
   //---------------------------------------------------------------
   if(PesoEma > 0.0)
     {
      double sig = 0.0;
      bool crossUp   = (s.emaFastPrev <= s.emaSlowPrev && s.emaFastNow >  s.emaSlowNow);
      bool crossDown = (s.emaFastPrev >= s.emaSlowPrev && s.emaFastNow <  s.emaSlowNow);

      if(crossUp)                          sig =  1.0;
      else if(crossDown)                   sig = -1.0;
      else if(s.emaFastNow > s.emaSlowNow) sig =  0.5;
      else if(s.emaFastNow < s.emaSlowNow) sig = -0.5;

      weightedSum += sig * PesoEma;
      weightTotal += PesoEma;
     }

   //---------------------------------------------------------------
   // 2) RSI
   //---------------------------------------------------------------
   if(PesoRsi > 0.0)
     {
      double sig = 0.0;

      if(RsiModo == MESA_RSI_REVERSION)
        {
         //--- Extremos como exaustao: sobrevenda compra, sobrecompra vende
         if(s.rsiNow <= (double)RsiNivelSobrevenda)
            sig =  1.0;
         else if(s.rsiNow >= (double)RsiNivelSobrecompra)
            sig = -1.0;
         else
            sig = 0.0;
        }
      else
        {
         //--- Momentum: distancia normalizada da linha de 50
         sig = (s.rsiNow - 50.0) / 50.0;
         //--- Zonas extremas reduzem conviccao (risco de exaustao)
         if(s.rsiNow >= (double)RsiNivelSobrecompra) sig *= 0.5;
         if(s.rsiNow <= (double)RsiNivelSobrevenda)  sig *= 0.5;
        }

      sig = ClampDouble(sig, -1.0, 1.0);
      weightedSum += sig * PesoRsi;
      weightTotal += PesoRsi;
     }

   //---------------------------------------------------------------
   // 3) MACD - lado e aceleracao do histograma
   //---------------------------------------------------------------
   if(PesoMacd > 0.0)
     {
      double sig = 0.0;
      bool rising  = (s.macdHistNow > s.macdHistPrev);
      bool falling = (s.macdHistNow < s.macdHistPrev);

      if(s.macdHistNow > 0.0)      sig = rising  ?  1.0 :  0.5;
      else if(s.macdHistNow < 0.0) sig = falling ? -1.0 : -0.5;

      //--- Confirmacao pela linha principal acima/abaixo de zero
      if(s.macdMainNow > 0.0 && sig > 0.0) sig = MathMin(1.0, sig + 0.1);
      if(s.macdMainNow < 0.0 && sig < 0.0) sig = MathMax(-1.0, sig - 0.1);

      weightedSum += sig * PesoMacd;
      weightTotal += PesoMacd;
     }

   //---------------------------------------------------------------
   // 4) Bandas de Bollinger - posicao relativa no envelope
   //---------------------------------------------------------------
   if(PesoBollinger > 0.0)
     {
      double sig   = 0.0;
      double width = s.bbUpperNow - s.bbLowerNow;

      if(width > 0.0)
        {
         //--- pos = 0 na banda inferior, 1 na superior
         double pos = (s.closeNow - s.bbLowerNow) / width;
         pos = ClampDouble(pos, 0.0, 1.0);

         if(s.closeNow <= s.bbLowerNow)      sig =  1.0;   // rompeu a inferior
         else if(s.closeNow >= s.bbUpperNow) sig = -1.0;   // rompeu a superior
         else                                sig = (0.5 - pos) * 2.0;
        }

      sig = ClampDouble(sig, -1.0, 1.0);
      weightedSum += sig * PesoBollinger;
      weightTotal += PesoBollinger;
     }

   //---------------------------------------------------------------
   // 5) ADX - direcao (+DI/-DI) escalada pela forca da tendencia
   //---------------------------------------------------------------
   if(PesoAdx > 0.0)
     {
      double sig      = 0.0;
      double diSum    = s.plusDiNow + s.minusDiNow;
      double strength = ClampDouble(s.adxNow / 50.0, 0.0, 1.0);

      if(diSum > 0.0)
         sig = ((s.plusDiNow - s.minusDiNow) / diSum) * strength;

      sig = ClampDouble(sig, -1.0, 1.0);
      weightedSum += sig * PesoAdx;
      weightTotal += PesoAdx;
     }

   if(weightTotal <= 0.0)
      return(0.0);

   double score = (weightedSum / weightTotal) * 100.0;
   return(ClampDouble(score, -100.0, 100.0));
  }

//==================================================================//
//  SECAO 4 - FILTROS DE TEMPO                                      //
//==================================================================//

//+------------------------------------------------------------------+
//| MinutesOfDay - converte hora/minuto em minutos desde 00:00       |
//+------------------------------------------------------------------+
int MinutesOfDay(const int hour, const int minute)
  {
   return(hour * 60 + minute);
  }

//+------------------------------------------------------------------+
//| IsInsideMinuteWindow - janela [start, end) com suporte a         |
//| viradas de meia-noite (ex.: 22:00 -> 03:00).                     |
//| start == end e interpretado como janela de 24 horas.             |
//+------------------------------------------------------------------+
bool IsInsideMinuteWindow(const int nowMin, const int startMin, const int endMin)
  {
   if(startMin == endMin)
      return(true);                                   // 24 horas liberadas

   if(startMin < endMin)
      return(nowMin >= startMin && nowMin < endMin);  // janela no mesmo dia

   return(nowMin >= startMin || nowMin < endMin);     // janela cruza a meia-noite
  }

//+------------------------------------------------------------------+
//| IsValueInCsvList - parser de lista CSV com intervalos            |
//|                                                                  |
//| Aceita formatos como "1,2,15-20,31" ou "1-6,9,10-12".            |
//| Lista vazia ou "*" libera qualquer valor.                        |
//| Intervalos invertidos ("20-15") sao normalizados.                |
//+------------------------------------------------------------------+
bool IsValueInCsvList(const string csv, const int value)
  {
   string list = csv;
   StringTrimLeft(list);
   StringTrimRight(list);

   if(StringLen(list) == 0 || list == "*")
      return(true);

   string parts[];
   int count = StringSplit(list, StringGetCharacter(",", 0), parts);
   if(count <= 0)
      return(true);

   for(int i = 0; i < count; i++)
     {
      string token = parts[i];
      StringTrimLeft(token);
      StringTrimRight(token);
      if(StringLen(token) == 0)
         continue;

      int dashPos = StringFind(token, "-");

      //--- dashPos > 0 assegura que nao estamos lendo um numero negativo
      if(dashPos > 0)
        {
         string leftPart  = StringSubstr(token, 0, dashPos);
         string rightPart = StringSubstr(token, dashPos + 1);
         StringTrimLeft(leftPart);   StringTrimRight(leftPart);
         StringTrimLeft(rightPart);  StringTrimRight(rightPart);

         if(StringLen(leftPart) == 0 || StringLen(rightPart) == 0)
            continue;

         int lo = (int)StringToInteger(leftPart);
         int hi = (int)StringToInteger(rightPart);
         if(lo > hi)
           {
            int swap = lo;
            lo = hi;
            hi = swap;
           }
         if(value >= lo && value <= hi)
            return(true);
        }
      else
        {
         if((int)StringToInteger(token) == value)
            return(true);
        }
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| DateToStamp - formata a data como AAAA.MM.DD                     |
//+------------------------------------------------------------------+
string DateToStamp(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
  }

//+------------------------------------------------------------------+
//| IsBlackoutDate - verifica a data contra a lista de bloqueio      |
//| Formato esperado: "2026.01.01,2026.12.25"                        |
//+------------------------------------------------------------------+
bool IsBlackoutDate(const datetime t)
  {
   string list = DatasBlackout;
   StringTrimLeft(list);
   StringTrimRight(list);
   if(StringLen(list) == 0)
      return(false);

   string stamp = DateToStamp(t);

   string parts[];
   int count = StringSplit(list, StringGetCharacter(",", 0), parts);
   for(int i = 0; i < count; i++)
     {
      string token = parts[i];
      StringTrimLeft(token);
      StringTrimRight(token);
      if(StringLen(token) == 0)
         continue;
      if(token == stamp)
         return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| IsWeekdayAllowed - traduz os sete inputs booleanos               |
//+------------------------------------------------------------------+
bool IsWeekdayAllowed(const int dayOfWeek)
  {
   switch(dayOfWeek)
     {
      case 0: return(OperarDomingo);
      case 1: return(OperarSegunda);
      case 2: return(OperarTerca);
      case 3: return(OperarQuarta);
      case 4: return(OperarQuinta);
      case 5: return(OperarSexta);
      case 6: return(OperarSabado);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| WeekdayName - nome do dia da semana em portugues                 |
//+------------------------------------------------------------------+
string WeekdayName(const int dayOfWeek)
  {
   switch(dayOfWeek)
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

//+------------------------------------------------------------------+
//| IsInsideHourWindow - janela HoraInicio:MinutoInicio ate          |
//| HoraFim:MinutoFim, tolerando a virada de meia-noite.             |
//+------------------------------------------------------------------+
bool IsInsideHourWindow(const datetime t)
  {
   if(!UsarFiltroHorario)
      return(true);

   MqlDateTime dt;
   TimeToStruct(t, dt);

   int nowMin   = MinutesOfDay(dt.hour, dt.min);
   int startMin = MinutesOfDay(HoraInicio, MinutoInicio);
   int endMin   = MinutesOfDay(HoraFim, MinutoFim);

   return(IsInsideMinuteWindow(nowMin, startMin, endMin));
  }

//+------------------------------------------------------------------+
//| IsInsideSession - checa as sessoes habilitadas em horario GMT    |
//|                                                                  |
//| A hora do servidor e convertida para GMT subtraindo o offset     |
//| informado pelo operador (OffsetGmtServidor).                     |
//+------------------------------------------------------------------+
bool IsInsideSession(const datetime serverTime)
  {
   if(!UsarFiltroSessao)
      return(true);

   //--- Se nenhuma sessao foi marcada, o filtro nao pode liberar nada
   if(!SessaoAsia && !SessaoLondres && !SessaoNovaYork)
      return(false);

   datetime gmtTime = serverTime - (datetime)(OffsetGmtServidor * 3600);

   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   int nowMin = MinutesOfDay(dt.hour, dt.min);

   if(SessaoAsia &&
      IsInsideMinuteWindow(nowMin, MinutesOfDay(AsiaInicioGmt, 0), MinutesOfDay(AsiaFimGmt, 0)))
      return(true);

   if(SessaoLondres &&
      IsInsideMinuteWindow(nowMin, MinutesOfDay(LondresInicioGmt, 0), MinutesOfDay(LondresFimGmt, 0)))
      return(true);

   if(SessaoNovaYork &&
      IsInsideMinuteWindow(nowMin, MinutesOfDay(NovaYorkInicioGmt, 0), MinutesOfDay(NovaYorkFimGmt, 0)))
      return(true);

   return(false);
  }

//+------------------------------------------------------------------+
//| ResetFilterStatus - assume tudo liberado antes da avaliacao      |
//+------------------------------------------------------------------+
void ResetFilterStatus(FilterStatus &f)
  {
   f.terminalOk   = true;
   f.spreadOk     = true;
   f.hourOk       = true;
   f.weekdayOk    = true;
   f.dayOfMonthOk = true;
   f.monthOk      = true;
   f.yearOk       = true;
   f.blackoutOk   = true;
   f.sessionOk    = true;
   f.dailyLossOk  = true;
   f.dailyGoalOk  = true;
   f.tradeCountOk = true;
   f.exposureOk   = true;
   f.volatilityOk = true;
   f.reason       = "LIBERADO";
  }

//+------------------------------------------------------------------+
//| IsTradingAllowed - AGREGADOR UNICO DE TODOS OS FILTROS           |
//|                                                                  |
//| Avalia, na ordem: contexto do terminal, calendario (ano, mes,    |
//| dia do mes, dia da semana, blackout), horario, sessao, spread,   |
//| volatilidade, limites diarios de caixa e exposicao.              |
//|                                                                  |
//| Todos os filtros sao avaliados (nao ha curto-circuito) para que  |
//| o painel mostre o quadro completo; "reason" recebe o motivo do   |
//| PRIMEIRO bloqueio encontrado, que e o que interessa ao log.      |
//+------------------------------------------------------------------+
bool IsTradingAllowed(datetime t, string &reason)
  {
   ResetFilterStatus(g_filters);

   MqlDateTime dt;
   TimeToStruct(t, dt);

   //---------------------------------------------------------------
   // 1) Contexto de negociacao do terminal, da conta e do expert
   //---------------------------------------------------------------
   g_filters.terminalOk = IsTradeContextReady();

   //---------------------------------------------------------------
   // 2) Filtro de ANO
   //---------------------------------------------------------------
   if(UsarFiltroAno)
      g_filters.yearOk = (dt.year >= AnoMinimo && dt.year <= AnoMaximo);

   //---------------------------------------------------------------
   // 3) Filtro de MES (lista CSV com intervalos)
   //---------------------------------------------------------------
   if(UsarFiltroMes)
      g_filters.monthOk = IsValueInCsvList(MesesPermitidos, dt.mon);

   //---------------------------------------------------------------
   // 4) Filtro de DIA DO MES (lista CSV com intervalos)
   //---------------------------------------------------------------
   if(UsarFiltroDiaDoMes)
      g_filters.dayOfMonthOk = IsValueInCsvList(DiasDoMesPermitidos, dt.day);

   //---------------------------------------------------------------
   // 5) Filtro de DIA DA SEMANA
   //---------------------------------------------------------------
   g_filters.weekdayOk = IsWeekdayAllowed(dt.day_of_week);

   //---------------------------------------------------------------
   // 6) Filtro de BLACKOUT (feriados, NFP, datas sensiveis)
   //---------------------------------------------------------------
   if(UsarBlackout)
      g_filters.blackoutOk = !IsBlackoutDate(t);

   //---------------------------------------------------------------
   // 7) Filtro de HORARIO (janela podendo cruzar a meia-noite)
   //---------------------------------------------------------------
   g_filters.hourOk = IsInsideHourWindow(t);

   //---------------------------------------------------------------
   // 8) Filtro de SESSAO (Asia / Londres / Nova York em GMT)
   //---------------------------------------------------------------
   g_filters.sessionOk = IsInsideSession(t);

   //---------------------------------------------------------------
   // 9) Filtro de SPREAD
   //---------------------------------------------------------------
   int spread = CurrentSpreadPoints();
   g_filters.spreadOk = (SpreadMaximoPontos <= 0 || spread <= SpreadMaximoPontos);

   //---------------------------------------------------------------
   // 10) Filtro de VOLATILIDADE por ATR
   //---------------------------------------------------------------
   if(UsarFiltroVolatilidade && g_snapshot.valid)
     {
      double point = g_symbol.Point();
      if(point > 0.0)
        {
         double atrPoints = g_snapshot.atrNow / point;
         if(AtrMinimoPontos > 0.0 && atrPoints < AtrMinimoPontos) g_filters.volatilityOk = false;
         if(AtrMaximoPontos > 0.0 && atrPoints > AtrMaximoPontos) g_filters.volatilityOk = false;
        }
     }

   //---------------------------------------------------------------
   // 11) Limites diarios de caixa (perda maxima e meta de ganho)
   //---------------------------------------------------------------
   double dayPnL = g_dayRealizedPnL + (IncluirFlutuanteNoLimite ? g_dayFloatingPnL : 0.0);
   double dayPct = (g_dayStartBalance > 0.0) ? (dayPnL / g_dayStartBalance) * 100.0 : 0.0;

   if(UsarLimitePerdaDiaria && PerdaDiariaMaximaPct > 0.0)
      g_filters.dailyLossOk = (dayPct > -PerdaDiariaMaximaPct);

   if(UsarMetaGanhoDiario && MetaGanhoDiarioPct > 0.0)
      g_filters.dailyGoalOk = (dayPct < MetaGanhoDiarioPct);

   //---------------------------------------------------------------
   // 12) Limite de trades no dia
   //---------------------------------------------------------------
   if(MaxTradesPorDia > 0)
      g_filters.tradeCountOk = (g_dayTradeCount < MaxTradesPorDia);

   //---------------------------------------------------------------
   // 13) Exposicao maxima simultanea
   //---------------------------------------------------------------
   g_filters.exposureOk = (CountOwnPositions() < MaxPosicoesSimultaneas);

   //---------------------------------------------------------------
   // Consolidacao: primeiro motivo de bloqueio vira "reason"
   //---------------------------------------------------------------
   if(!g_filters.terminalOk)        g_filters.reason = "Contexto de trading indisponivel";
   else if(!g_filters.yearOk)       g_filters.reason = StringFormat("Ano %d fora da faixa permitida", dt.year);
   else if(!g_filters.monthOk)      g_filters.reason = StringFormat("Mes %d nao permitido", dt.mon);
   else if(!g_filters.dayOfMonthOk) g_filters.reason = StringFormat("Dia %d nao permitido", dt.day);
   else if(!g_filters.weekdayOk)    g_filters.reason = StringFormat("%s bloqueado", WeekdayName(dt.day_of_week));
   else if(!g_filters.blackoutOk)   g_filters.reason = "Data em blackout: " + DateToStamp(t);
   else if(!g_filters.hourOk)       g_filters.reason = StringFormat("Fora da janela %02d:%02d-%02d:%02d",
                                                                   HoraInicio, MinutoInicio, HoraFim, MinutoFim);
   else if(!g_filters.sessionOk)    g_filters.reason = "Fora das sessoes habilitadas";
   else if(!g_filters.spreadOk)     g_filters.reason = StringFormat("Spread %d > maximo %d", spread, SpreadMaximoPontos);
   else if(!g_filters.volatilityOk) g_filters.reason = "Volatilidade (ATR) fora da faixa";
   else if(!g_filters.dailyLossOk)  g_filters.reason = StringFormat("Perda diaria atingida (%.2f%%)", dayPct);
   else if(!g_filters.dailyGoalOk)  g_filters.reason = StringFormat("Meta diaria atingida (%.2f%%)", dayPct);
   else if(!g_filters.tradeCountOk) g_filters.reason = StringFormat("Limite de %d trades/dia atingido", MaxTradesPorDia);
   else if(!g_filters.exposureOk)   g_filters.reason = StringFormat("Exposicao maxima (%d posicoes)", MaxPosicoesSimultaneas);
   else                             g_filters.reason = "LIBERADO";

   reason = g_filters.reason;

   return(g_filters.terminalOk   && g_filters.yearOk       && g_filters.monthOk      &&
          g_filters.dayOfMonthOk && g_filters.weekdayOk    && g_filters.blackoutOk   &&
          g_filters.hourOk       && g_filters.sessionOk    && g_filters.spreadOk     &&
          g_filters.volatilityOk && g_filters.dailyLossOk  && g_filters.dailyGoalOk  &&
          g_filters.tradeCountOk && g_filters.exposureOk);
  }

//==================================================================//
//  SECAO 5 - GESTAO DE RISCO                                       //
//==================================================================//

//+------------------------------------------------------------------+
//| NormalizeVolume - ajusta o lote ao passo, minimo e maximo do     |
//| simbolo, respeitando ainda o teto interno da mesa.               |
//+------------------------------------------------------------------+
double NormalizeVolume(const double rawVolume)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0) step = 0.01;
   if(minV <= 0.0) minV = step;
   if(maxV <= 0.0) maxV = 100.0;

   //--- Teto de governanca da mesa
   if(LoteMaximoPermitido > 0.0)
      maxV = MathMin(maxV, LoteMaximoPermitido);

   double volume = MathFloor(rawVolume / step) * step;

   if(volume < minV) volume = minV;
   if(volume > maxV) volume = maxV;

   //--- Casas decimais derivadas do passo de volume
   int digits = 2;
   if(step > 0.0)
     {
      double d = -MathLog10(step);
      digits = (int)MathMax(0.0, MathCeil(d - 0.0000001));
     }

   return(NormalizeDouble(volume, digits));
  }

//+------------------------------------------------------------------+
//| CalculateLotSize - dimensiona a posicao                          |
//|                                                                  |
//| No modo de risco percentual, o tamanho decorre da perda maxima   |
//| aceita em dinheiro dividida pela perda por lote na distancia do  |
//| stop, usando TICK_VALUE e TICK_SIZE do simbolo. E o metodo       |
//| correto para manter risco constante entre ativos diferentes.     |
//+------------------------------------------------------------------+
double CalculateLotSize(const double stopDistancePrice)
  {
   if(ModoLote == MESA_LOT_FIXED)
      return(NormalizeVolume(LoteFixo));

   if(stopDistancePrice <= 0.0)
      return(NormalizeVolume(LoteFixo));

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return(NormalizeVolume(LoteFixo));

   double riskMoney = balance * (RiscoPorTradePct / 100.0);
   if(riskMoney <= 0.0)
      return(NormalizeVolume(LoteFixo));

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0)
     {
      Print("[MESA] TICK_VALUE/TICK_SIZE indisponiveis; usando lote fixo por seguranca.");
      return(NormalizeVolume(LoteFixo));
     }

   //--- Prejuizo, em dinheiro, de 1 lote se o stop for acionado
   double lossPerLot = (stopDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return(NormalizeVolume(LoteFixo));

   return(NormalizeVolume(riskMoney / lossPerLot));
  }

//+------------------------------------------------------------------+
//| MinStopDistance - distancia minima exigida pela corretora        |
//+------------------------------------------------------------------+
double MinStopDistance()
  {
   int level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(level <= 0)
      return(0.0);
   return((double)level * g_symbol.Point());
  }

//+------------------------------------------------------------------+
//| StopDistanceInPrice - distancia do stop em unidades de preco     |
//+------------------------------------------------------------------+
double StopDistanceInPrice(const double atr)
  {
   double distance = 0.0;

   if(ModoStop == MESA_STOP_ATR)
      distance = atr * AtrMultiploStop;
   else
      distance = (double)StopPontos * g_symbol.Point();

   //--- Nunca abaixo do nivel minimo da corretora
   double minDist = MinStopDistance();
   if(minDist > 0.0 && distance < minDist)
      distance = minDist;

   return(distance);
  }

//+------------------------------------------------------------------+
//| TargetDistanceInPrice - distancia do alvo em unidades de preco   |
//+------------------------------------------------------------------+
double TargetDistanceInPrice(const double atr)
  {
   double distance = 0.0;

   if(ModoStop == MESA_STOP_ATR)
      distance = atr * AtrMultiploAlvo;
   else
      distance = (double)AlvoPontos * g_symbol.Point();

   double minDist = MinStopDistance();
   if(minDist > 0.0 && distance < minDist)
      distance = minDist;

   return(distance);
  }

//+------------------------------------------------------------------+
//| CurrentSpreadPoints - spread corrente em pontos                  |
//+------------------------------------------------------------------+
int CurrentSpreadPoints()
  {
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > 0)
      return(spread);

   //--- Fallback para simbolos com spread flutuante nao publicado
   double point = g_symbol.Point();
   if(point <= 0.0)
      return(0);

   return((int)MathRound((g_symbol.Ask() - g_symbol.Bid()) / point));
  }

//+------------------------------------------------------------------+
//| CountOwnPositions - posicoes do simbolo com o nosso magic        |
//+------------------------------------------------------------------+
int CountOwnPositions()
  {
   int total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_position.SelectByIndex(i))
         continue;
      if(g_position.Symbol() != _Symbol)
         continue;
      if((long)g_position.Magic() != MagicNumber)
         continue;
      total++;
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| CountOwnPositionsByType - posicoes por direcao                   |
//+------------------------------------------------------------------+
int CountOwnPositionsByType(const ENUM_POSITION_TYPE type)
  {
   int total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_position.SelectByIndex(i))
         continue;
      if(g_position.Symbol() != _Symbol)
         continue;
      if((long)g_position.Magic() != MagicNumber)
         continue;
      if(g_position.PositionType() != type)
         continue;
      total++;
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| StartOfDay - meia-noite do dia informado (hora do servidor)      |
//+------------------------------------------------------------------+
datetime StartOfDay(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return(StructToTime(dt));
  }

//+------------------------------------------------------------------+
//| UpdateDailyStats - reconstroi a caixa do dia pelo historico      |
//|                                                                  |
//| Reconstruir a partir do historico (em vez de guardar contadores  |
//| em memoria) mantem os limites corretos apos reinicio do          |
//| terminal ou troca de timeframe.                                  |
//+------------------------------------------------------------------+
void UpdateDailyStats()
  {
   datetime now      = TimeCurrent();
   datetime dayStart = StartOfDay(now);

   if(dayStart != g_dayStart)
     {
      g_dayStart = dayStart;
      if(LogDetalhado)
         PrintFormat("[MESA] Novo pregao iniciado em %s", TimeToString(dayStart, TIME_DATE));
     }

   double realized = 0.0;
   int    trades   = 0;

   if(HistorySelect(dayStart, now + 1))
     {
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;

         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
            continue;
         if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
            continue;

         ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
            continue;

         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
            trades++;

         realized += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         realized += HistoryDealGetDouble(ticket, DEAL_SWAP);
         realized += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
        }
     }

   //--- Resultado flutuante das posicoes proprias
   double floating = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_position.SelectByIndex(i))
         continue;
      if(g_position.Symbol() != _Symbol)
         continue;
      if((long)g_position.Magic() != MagicNumber)
         continue;
      //--- Comissao de posicao aberta nao e exposta pela API; ela ja
      //--- entra no realizado quando o negocio de saida e registrado.
      floating += g_position.Profit() + g_position.Swap();
     }

   g_dayRealizedPnL = realized;
   g_dayFloatingPnL = floating;
   g_dayTradeCount  = trades;

   //--- Saldo de abertura do dia = saldo atual menos o realizado hoje
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dayStartBalance = balance - realized;
   if(g_dayStartBalance <= 0.0)
      g_dayStartBalance = (balance > 0.0 ? balance : 1.0);
  }

//==================================================================//
//  SECAO 6 - EXECUCAO E GESTAO DE POSICOES                         //
//==================================================================//

//+------------------------------------------------------------------+
//| IsNewBar - true apenas no primeiro tick de uma nova barra        |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime currentBarTime = iTime(_Symbol, g_timeframe, 0);
   if(currentBarTime == 0)
      return(false);

   if(currentBarTime == g_lastBarTime)
      return(false);

   g_lastBarTime = currentBarTime;
   return(true);
  }

//+------------------------------------------------------------------+
//| IsTradeContextReady - checagens de permissao de negociacao       |
//+------------------------------------------------------------------+
bool IsTradeContextReady()
  {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return(false);
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return(false);
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return(false);
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return(false);
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| ProcessSignal - avalia filtros, calcula o score e decide entrada |
//+------------------------------------------------------------------+
void ProcessSignal()
  {
   //--- 1) Fotografia dos indicadores
   if(!ReadIndicators(g_snapshot))
     {
      if(LogDetalhado)
         PrintFormat("[MESA] Indicadores ainda sem dados suficientes. Erro: %d", _LastError);
      return;
     }

   //--- 2) Score ponderado
   g_lastScore = ComputeScore(g_snapshot);

   //--- 3) Bateria completa de filtros
   string reason = "";
   if(!IsTradingAllowed(TimeCurrent(), reason))
     {
      if(LogDetalhado)
         PrintFormat("[MESA] Entrada bloqueada | Score %.1f | Motivo: %s", g_lastScore, reason);
      return;
     }

   //--- 4) Filtro de forca de tendencia (ADX)
   if(AdxMinimo > 0.0 && g_snapshot.adxNow < AdxMinimo)
     {
      if(LogDetalhado)
         PrintFormat("[MESA] ADX %.1f abaixo do minimo %.1f - sem entrada.", g_snapshot.adxNow, AdxMinimo);
      return;
     }

   //--- 5) Decisao direcional
   if(g_lastScore >= LimiarCompra)
      TryOpenPosition(ORDER_TYPE_BUY);
   else if(g_lastScore <= -LimiarVenda)
      TryOpenPosition(ORDER_TYPE_SELL);
  }

//+------------------------------------------------------------------+
//| TryOpenPosition - monta e envia a ordem a mercado                |
//+------------------------------------------------------------------+
bool TryOpenPosition(const ENUM_ORDER_TYPE orderType)
  {
   if(!g_symbol.RefreshRates())
      return(false);

   ENUM_POSITION_TYPE sameSide = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY  : POSITION_TYPE_SELL;
   ENUM_POSITION_TYPE otherSide = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;

   //--- Politica de posicoes opostas
   if(!PermitirPosicoesOpostas && CountOwnPositionsByType(otherSide) > 0)
     {
      if(LogDetalhado)
         Print("[MESA] Posicao oposta aberta e hedge desabilitado - entrada descartada.");
      return(false);
     }

   //--- Reforco do teto de exposicao (situacao pode ter mudado no tick)
   if(CountOwnPositions() >= MaxPosicoesSimultaneas)
      return(false);
   if(CountOwnPositionsByType(sameSide) >= MaxPosicoesSimultaneas)
      return(false);

   double atr        = g_snapshot.atrNow;
   double stopDist   = StopDistanceInPrice(atr);
   double targetDist = TargetDistanceInPrice(atr);

   if(stopDist <= 0.0)
     {
      Print("[MESA] Distancia de stop invalida - entrada abortada.");
      return(false);
     }

   int    digits = g_symbol.Digits();
   double price  = (orderType == ORDER_TYPE_BUY) ? g_symbol.Ask() : g_symbol.Bid();
   double sl     = 0.0;
   double tp     = 0.0;

   if(orderType == ORDER_TYPE_BUY)
     {
      sl = NormalizeDouble(price - stopDist,   digits);
      tp = NormalizeDouble(price + targetDist, digits);
     }
   else
     {
      sl = NormalizeDouble(price + stopDist,   digits);
      tp = NormalizeDouble(price - targetDist, digits);
     }

   //--- Dimensionamento pelo risco
   double volume = CalculateLotSize(stopDist);
   if(volume <= 0.0)
     {
      Print("[MESA] Volume calculado invalido - entrada abortada.");
      return(false);
     }

   //--- Margem disponivel
   double marginRequired = 0.0;
   if(OrderCalcMargin(orderType, _Symbol, volume, price, marginRequired))
     {
      if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
        {
         PrintFormat("[MESA] Margem insuficiente. Necessario %.2f, livre %.2f.",
                     marginRequired, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
         return(false);
        }
     }

   bool sent = false;
   if(orderType == ORDER_TYPE_BUY)
      sent = g_trade.Buy(volume, _Symbol, price, sl, tp, ComentarioOrdem);
   else
      sent = g_trade.Sell(volume, _Symbol, price, sl, tp, ComentarioOrdem);

   uint retcode = g_trade.ResultRetcode();

   if(!sent || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED))
     {
      PrintFormat("[MESA] Falha na entrada %s | retcode %u (%s) | erro %d",
                  (orderType == ORDER_TYPE_BUY ? "COMPRA" : "VENDA"),
                  retcode, g_trade.ResultRetcodeDescription(), _LastError);
      ResetLastError();
      return(false);
     }

   PrintFormat("[MESA] %s executada | vol %.2f | preco %s | SL %s | TP %s | score %.1f | ATR %.5f",
               (orderType == ORDER_TYPE_BUY ? "COMPRA" : "VENDA"),
               volume,
               DoubleToString(g_trade.ResultPrice(), digits),
               DoubleToString(sl, digits),
               DoubleToString(tp, digits),
               g_lastScore,
               atr);

   return(true);
  }

//+------------------------------------------------------------------+
//| ManageOpenPositions - aplica break-even e trailing stop          |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   if(!UsarBreakEven && ModoTrailing == MESA_TRAIL_OFF)
      return;

   if(PositionsTotal() == 0)
      return;

   //--- ATR corrente para os modos baseados em volatilidade
   double atr = g_snapshot.valid ? g_snapshot.atrNow : 0.0;
   if(atr <= 0.0)
     {
      double atrBuf[];
      if(CopyIndicatorValues(g_hAtr, 0, 2, atrBuf))
         atr = atrBuf[1];
     }

   int    digits = g_symbol.Digits();
   double point  = g_symbol.Point();
   if(point <= 0.0)
      return;

   double minDist = MinStopDistance();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_position.SelectByIndex(i))
         continue;
      if(g_position.Symbol() != _Symbol)
         continue;
      if((long)g_position.Magic() != MagicNumber)
         continue;

      ulong  ticket    = g_position.Ticket();
      double openPrice = g_position.PriceOpen();
      double currentSL = g_position.StopLoss();
      double currentTP = g_position.TakeProfit();
      bool   isBuy     = (g_position.PositionType() == POSITION_TYPE_BUY);
      double marketPx  = isBuy ? g_symbol.Bid() : g_symbol.Ask();

      double newSL = currentSL;

      //-----------------------------------------------------------
      // Break-even: trava o capital assim que o gatilho e superado
      //-----------------------------------------------------------
      if(UsarBreakEven)
        {
         double trigger = (ModoStop == MESA_STOP_ATR && atr > 0.0)
                          ? atr * BreakEvenGatilhoAtr
                          : (double)BreakEvenGatilhoPontos * point;

         double offset  = (double)BreakEvenOffsetPontos * point;
         double profit  = isBuy ? (marketPx - openPrice) : (openPrice - marketPx);

         if(trigger > 0.0 && profit >= trigger)
           {
            double bePrice = isBuy ? (openPrice + offset) : (openPrice - offset);
            bePrice = NormalizeDouble(bePrice, digits);

            if(isBuy)
              {
               if(currentSL < bePrice)
                  newSL = bePrice;
              }
            else
              {
               if(currentSL > bePrice || currentSL == 0.0)
                  newSL = bePrice;
              }
           }
        }

      //-----------------------------------------------------------
      // Trailing stop: acompanha o preco preservando o lucro aberto
      //-----------------------------------------------------------
      if(ModoTrailing != MESA_TRAIL_OFF)
        {
         double trailDist = 0.0;
         if(ModoTrailing == MESA_TRAIL_ATR && atr > 0.0)
            trailDist = atr * TrailingAtrMultiplo;
         else if(ModoTrailing == MESA_TRAIL_POINTS)
            trailDist = (double)TrailingPontos * point;

         if(trailDist > 0.0)
           {
            if(minDist > 0.0 && trailDist < minDist)
               trailDist = minDist;

            double candidate = isBuy ? (marketPx - trailDist) : (marketPx + trailDist);
            candidate = NormalizeDouble(candidate, digits);

            //--- So move na direcao do lucro e apenas se ja houver ganho
            if(isBuy && candidate > openPrice)
              {
               if(candidate > newSL || newSL == 0.0)
                  newSL = candidate;
              }
            else if(!isBuy && candidate < openPrice)
              {
               if(candidate < newSL || newSL == 0.0)
                  newSL = candidate;
              }
           }
        }

      //-----------------------------------------------------------
      // Envio da modificacao, respeitando passo minimo e stop level
      //-----------------------------------------------------------
      if(newSL == currentSL || newSL == 0.0)
         continue;

      double stepPrice = (double)TrailingPassoPontos * point;
      if(currentSL != 0.0 && MathAbs(newSL - currentSL) < stepPrice)
         continue;

      //--- Nao aceitar stop dentro do nivel congelado da corretora
      if(minDist > 0.0)
        {
         if(isBuy  && (marketPx - newSL) < minDist) continue;
         if(!isBuy && (newSL - marketPx) < minDist) continue;
        }

      //--- Nunca colocar o stop do lado errado do preco
      if(isBuy  && newSL >= marketPx) continue;
      if(!isBuy && newSL <= marketPx) continue;

      if(!g_trade.PositionModify(ticket, newSL, currentTP))
        {
         PrintFormat("[MESA] Falha ao ajustar stop do ticket %I64u | retcode %u (%s) | erro %d",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription(), _LastError);
         ResetLastError();
        }
      else if(LogDetalhado)
        {
         PrintFormat("[MESA] Stop do ticket %I64u movido para %s",
                     ticket, DoubleToString(newSL, digits));
        }
     }
  }

//+------------------------------------------------------------------+
//| CloseAllOwnPositions - zera a exposicao da mesa no simbolo       |
//+------------------------------------------------------------------+
void CloseAllOwnPositions(const string motive)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_position.SelectByIndex(i))
         continue;
      if(g_position.Symbol() != _Symbol)
         continue;
      if((long)g_position.Magic() != MagicNumber)
         continue;

      ulong ticket = g_position.Ticket();

      if(!g_trade.PositionClose(ticket))
        {
         PrintFormat("[MESA] Falha ao encerrar ticket %I64u | retcode %u (%s) | erro %d",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription(), _LastError);
         ResetLastError();
        }
      else
        {
         PrintFormat("[MESA] Ticket %I64u encerrado. Motivo: %s", ticket, motive);
        }
     }
  }

//+------------------------------------------------------------------+
//| HandleScheduledClosures - encerramentos de fim de janela/semana  |
//+------------------------------------------------------------------+
void HandleScheduledClosures()
  {
   datetime now = TimeCurrent();

   //--- Fim da janela de negociacao
   bool insideWindow = IsInsideHourWindow(now);
   if(FecharTudoNoFimDaJanela && UsarFiltroHorario)
     {
      if(g_wasInsideWindow && !insideWindow && CountOwnPositions() > 0)
         CloseAllOwnPositions("fim da janela de negociacao");
     }
   g_wasInsideWindow = insideWindow;

   //--- Encerramento de sexta-feira (evita carregar risco no fim de semana)
   if(FecharTudoNaSexta)
     {
      MqlDateTime dt;
      TimeToStruct(now, dt);
      if(dt.day_of_week == 5 && dt.hour >= HoraFechamentoSexta && CountOwnPositions() > 0)
         CloseAllOwnPositions("encerramento de sexta-feira");
     }
  }

//==================================================================//
//  SECAO 7 - PAINEL ON-CHART                                       //
//==================================================================//

//+------------------------------------------------------------------+
//| RefreshPanelState - recalcula estado e redesenha com throttle    |
//+------------------------------------------------------------------+
void RefreshPanelState()
  {
   if(!MostrarPainel)
      return;

   uint nowTick = GetTickCount();
   uint interval = (uint)MathMax(200, PainelIntervaloMs);

   if(nowTick - g_lastPanelTick < interval)
      return;

   g_lastPanelTick = nowTick;

   //--- Atualiza leituras e filtros para exibicao
   if(ReadIndicators(g_snapshot))
      g_lastScore = ComputeScore(g_snapshot);

   string reason = "";
   IsTradingAllowed(TimeCurrent(), reason);

   DrawPanel();
  }

//+------------------------------------------------------------------+
//| StatusText - rotulo padronizado de filtro                        |
//+------------------------------------------------------------------+
string StatusText(const bool ok)
  {
   return(ok ? "LIBERADO " : "BLOQUEADO");
  }

//+------------------------------------------------------------------+
//| BiasText - traduz o score em vies operacional                    |
//+------------------------------------------------------------------+
string BiasText(const double score)
  {
   if(score >= LimiarCompra)  return("COMPRA");
   if(score <= -LimiarVenda)  return("VENDA");
   if(score > 0.0)            return("neutro/alta");
   if(score < 0.0)            return("neutro/baixa");
   return("neutro");
  }

//+------------------------------------------------------------------+
//| DrawPanel - painel textual de acompanhamento da mesa             |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   if(!MostrarPainel)
      return;

   int    digits  = g_symbol.Digits();
   double dayPnL  = g_dayRealizedPnL + g_dayFloatingPnL;
   double dayPct  = (g_dayStartBalance > 0.0) ? (dayPnL / g_dayStartBalance) * 100.0 : 0.0;
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   string text = "";

   text += "==========================================================\n";
   text += "  MESA - Mesa de Operacoes Algoritmica            v1.00   \n";
   text += "==========================================================\n";
   text += StringFormat(" Simbolo: %-10s  Timeframe: %-8s  Magic: %I64d\n",
                        _Symbol, EnumToString(g_timeframe), MagicNumber);
   text += StringFormat(" Servidor: %s (%s)\n",
                        TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                        WeekdayName(dt.day_of_week));
   text += "----------------------------------------------------------\n";
   text += StringFormat(" SCORE: %+7.1f  /  100      Vies: %s\n", g_lastScore, BiasText(g_lastScore));
   text += StringFormat(" Limiares -> compra >= %+.1f | venda <= %+.1f\n", LimiarCompra, -LimiarVenda);
   text += "----------------------------------------------------------\n";
   text += " INDICADORES (ultima barra fechada)\n";

   if(g_snapshot.valid)
     {
      text += StringFormat("  EMA %d/%d : %s / %s  [%s]\n",
                           EmaRapidaPeriodo, EmaLentaPeriodo,
                           DoubleToString(g_snapshot.emaFastNow, digits),
                           DoubleToString(g_snapshot.emaSlowNow, digits),
                           (g_snapshot.emaFastNow > g_snapshot.emaSlowNow ? "alta" : "baixa"));
      text += StringFormat("  RSI(%d)   : %6.2f   (SC %d / SV %d)\n",
                           RsiPeriodo, g_snapshot.rsiNow, RsiNivelSobrecompra, RsiNivelSobrevenda);
      text += StringFormat("  MACD     : linha %s | sinal %s | hist %s\n",
                           DoubleToString(g_snapshot.macdMainNow, digits),
                           DoubleToString(g_snapshot.macdSignalNow, digits),
                           DoubleToString(g_snapshot.macdHistNow, digits));
      text += StringFormat("  ATR(%d)   : %s (%.0f pontos)\n",
                           AtrPeriodo,
                           DoubleToString(g_snapshot.atrNow, digits),
                           (g_symbol.Point() > 0.0 ? g_snapshot.atrNow / g_symbol.Point() : 0.0));
      text += StringFormat("  Bollinger: sup %s | med %s | inf %s\n",
                           DoubleToString(g_snapshot.bbUpperNow, digits),
                           DoubleToString(g_snapshot.bbMiddleNow, digits),
                           DoubleToString(g_snapshot.bbLowerNow, digits));
      text += StringFormat("  ADX(%d)   : %6.2f  (+DI %.2f / -DI %.2f) min %.1f\n",
                           AdxPeriodo, g_snapshot.adxNow,
                           g_snapshot.plusDiNow, g_snapshot.minusDiNow, AdxMinimo);
     }
   else
     {
      text += "  (aguardando dados suficientes dos indicadores)\n";
     }

   text += "----------------------------------------------------------\n";
   text += " FILTROS\n";
   text += StringFormat("  Contexto trading : %s\n", StatusText(g_filters.terminalOk));
   text += StringFormat("  Horario          : %s  (%02d:%02d - %02d:%02d)\n",
                        StatusText(g_filters.hourOk), HoraInicio, MinutoInicio, HoraFim, MinutoFim);
   text += StringFormat("  Dia da semana    : %s\n", StatusText(g_filters.weekdayOk));
   text += StringFormat("  Dia do mes       : %s\n", StatusText(g_filters.dayOfMonthOk));
   text += StringFormat("  Mes              : %s\n", StatusText(g_filters.monthOk));
   text += StringFormat("  Ano              : %s\n", StatusText(g_filters.yearOk));
   text += StringFormat("  Blackout         : %s\n", StatusText(g_filters.blackoutOk));
   text += StringFormat("  Sessao           : %s\n", StatusText(g_filters.sessionOk));
   text += StringFormat("  Spread           : %s  (%d / max %d)\n",
                        StatusText(g_filters.spreadOk), CurrentSpreadPoints(), SpreadMaximoPontos);
   text += StringFormat("  Volatilidade ATR : %s\n", StatusText(g_filters.volatilityOk));
   text += StringFormat("  Perda diaria     : %s\n", StatusText(g_filters.dailyLossOk));
   text += StringFormat("  Meta diaria      : %s\n", StatusText(g_filters.dailyGoalOk));
   text += StringFormat("  Trades/dia       : %s\n", StatusText(g_filters.tradeCountOk));
   text += StringFormat("  Exposicao        : %s\n", StatusText(g_filters.exposureOk));
   text += StringFormat("  >> STATUS: %s\n", g_filters.reason);

   text += "----------------------------------------------------------\n";
   text += " CAIXA DO DIA\n";
   text += StringFormat("  Saldo inicial : %.2f %s\n", g_dayStartBalance, currency);
   text += StringFormat("  Realizado     : %+.2f %s\n", g_dayRealizedPnL, currency);
   text += StringFormat("  Flutuante     : %+.2f %s\n", g_dayFloatingPnL, currency);
   text += StringFormat("  Resultado dia : %+.2f %s  (%+.2f%%)\n", dayPnL, currency, dayPct);
   text += StringFormat("  Trades hoje   : %d / %s\n",
                        g_dayTradeCount, (MaxTradesPorDia > 0 ? IntegerToString(MaxTradesPorDia) : "ilimitado"));
   text += StringFormat("  Posicoes      : %d / %d\n", CountOwnPositions(), MaxPosicoesSimultaneas);
   text += StringFormat("  Equity        : %.2f %s\n", AccountInfoDouble(ACCOUNT_EQUITY), currency);
   text += "==========================================================";

   Comment(text);
   ChartRedraw();
  }

//==================================================================//
//  SECAO 8 - UTILITARIOS                                           //
//==================================================================//

//+------------------------------------------------------------------+
//| ClampDouble - limita um valor a uma faixa                        |
//+------------------------------------------------------------------+
double ClampDouble(const double value, const double minValue, const double maxValue)
  {
   if(value < minValue) return(minValue);
   if(value > maxValue) return(maxValue);
   return(value);
  }

//+------------------------------------------------------------------+
//| ValidateInputs - critica de consistencia dos parametros          |
//+------------------------------------------------------------------+
bool ValidateInputs(string &errorText)
  {
   errorText = "";

   if(EmaRapidaPeriodo < 1 || EmaLentaPeriodo < 1)
     { errorText = "periodos de EMA devem ser >= 1"; return(false); }
   if(EmaRapidaPeriodo >= EmaLentaPeriodo)
     { errorText = "EMA rapida deve ter periodo menor que a EMA lenta"; return(false); }
   if(RsiPeriodo < 2)
     { errorText = "periodo do RSI deve ser >= 2"; return(false); }
   if(RsiNivelSobrevenda <= 0 || RsiNivelSobrecompra >= 100 || RsiNivelSobrevenda >= RsiNivelSobrecompra)
     { errorText = "niveis do RSI inconsistentes"; return(false); }
   if(MacdRapida < 1 || MacdLenta < 1 || MacdSinal < 1 || MacdRapida >= MacdLenta)
     { errorText = "parametros do MACD inconsistentes"; return(false); }
   if(AtrPeriodo < 1 || BollingerPeriodo < 2 || AdxPeriodo < 2)
     { errorText = "periodos de ATR/Bollinger/ADX inconsistentes"; return(false); }
   if(BollingerDesvio <= 0.0)
     { errorText = "desvio das Bandas de Bollinger deve ser > 0"; return(false); }

   if(PesoEma < 0.0 || PesoRsi < 0.0 || PesoMacd < 0.0 || PesoBollinger < 0.0 || PesoAdx < 0.0)
     { errorText = "pesos do motor de sinal nao podem ser negativos"; return(false); }
   if((PesoEma + PesoRsi + PesoMacd + PesoBollinger + PesoAdx) <= 0.0)
     { errorText = "ao menos um peso do motor de sinal deve ser maior que zero"; return(false); }
   if(LimiarCompra < 0.0 || LimiarCompra > 100.0 || LimiarVenda < 0.0 || LimiarVenda > 100.0)
     { errorText = "limiares de entrada devem estar entre 0 e 100"; return(false); }

   if(HoraInicio < 0 || HoraInicio > 23 || HoraFim < 0 || HoraFim > 23)
     { errorText = "horas da janela devem estar entre 0 e 23"; return(false); }
   if(MinutoInicio < 0 || MinutoInicio > 59 || MinutoFim < 0 || MinutoFim > 59)
     { errorText = "minutos da janela devem estar entre 0 e 59"; return(false); }

   if(UsarFiltroAno && AnoMinimo > AnoMaximo)
     { errorText = "ano minimo maior que o ano maximo"; return(false); }

   if(OffsetGmtServidor < -12 || OffsetGmtServidor > 14)
     { errorText = "offset GMT do servidor fora da faixa -12..+14"; return(false); }
   if(AsiaInicioGmt < 0 || AsiaInicioGmt > 23 || AsiaFimGmt < 0 || AsiaFimGmt > 23 ||
      LondresInicioGmt < 0 || LondresInicioGmt > 23 || LondresFimGmt < 0 || LondresFimGmt > 23 ||
      NovaYorkInicioGmt < 0 || NovaYorkInicioGmt > 23 || NovaYorkFimGmt < 0 || NovaYorkFimGmt > 23)
     { errorText = "horarios de sessao devem estar entre 0 e 23"; return(false); }

   if(ModoLote == MESA_LOT_FIXED && LoteFixo <= 0.0)
     { errorText = "lote fixo deve ser maior que zero"; return(false); }
   if(ModoLote == MESA_LOT_RISK && (RiscoPorTradePct <= 0.0 || RiscoPorTradePct > 100.0))
     { errorText = "risco por trade deve estar entre 0 e 100 por cento"; return(false); }

   if(ModoStop == MESA_STOP_ATR && (AtrMultiploStop <= 0.0 || AtrMultiploAlvo <= 0.0))
     { errorText = "multiplos de ATR para stop/alvo devem ser > 0"; return(false); }
   if(ModoStop == MESA_STOP_POINTS && (StopPontos <= 0 || AlvoPontos <= 0))
     { errorText = "stop/alvo em pontos devem ser > 0"; return(false); }

   if(MaxPosicoesSimultaneas < 1)
     { errorText = "maximo de posicoes simultaneas deve ser >= 1"; return(false); }
   if(UsarLimitePerdaDiaria && PerdaDiariaMaximaPct <= 0.0)
     { errorText = "perda diaria maxima deve ser > 0"; return(false); }
   if(UsarMetaGanhoDiario && MetaGanhoDiarioPct <= 0.0)
     { errorText = "meta de ganho diario deve ser > 0"; return(false); }

   if(HoraFechamentoSexta < 0 || HoraFechamentoSexta > 23)
     { errorText = "hora de fechamento de sexta deve estar entre 0 e 23"; return(false); }

   //--- Sem nenhum dia da semana habilitado o robo nunca operaria
   if(!OperarSegunda && !OperarTerca && !OperarQuarta && !OperarQuinta &&
      !OperarSexta   && !OperarSabado && !OperarDomingo)
     { errorText = "nenhum dia da semana habilitado"; return(false); }

   return(true);
  }
//+------------------------------------------------------------------+
