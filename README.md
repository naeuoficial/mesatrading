# MESA — Mesa de Operações Algorítmica

Painel web para operar robôs de MetaTrader: leitura de indicadores em tempo real,
gerador de Expert Advisors MQL5 e MQL4 com bateria completa de filtros temporais,
varredura de mesas proprietárias e diagnóstico das fontes de dados.

Dois arquivos HTML, sem build, sem dependências, sem `npm install`.

| | |
|---|---|
| **Painel de mesa** | [`index.html`](index.html) — multigráficos, análise por hover e botão direito |
| **Painel móvel** | [`index-mobile.html`](index-mobile.html) — gestos, modos de navegação, blocos reordenáveis |

---

## Começar

```bash
git clone https://github.com/naeuoficial/mesatrading.git
cd mesatrading
python3 -m http.server 8080
# http://localhost:8080
```

Abrir por `file://` funciona, mas alguns navegadores tratam a origem como opaca e
recusam o `fetch` — servindo por HTTP os provedores de dados liberam.

Para testar o móvel no celular, na mesma rede:
`http://<ip-da-máquina>:8080/index-mobile.html`

---

## O que tem dentro

**Gerador de robôs.** Configure estratégia, risco e filtros na interface e saia
com um `.mq5` ou `.mq4` compilável. O gerador não é um template com buracos: ele
produz o motor de sinal ponderado, a gestão de risco e a bateria de filtros
inteira, em código idiomático de cada plataforma — MQL5 com `CTrade` e
`CopyBuffer`, MQL4 com `OrderSend` e leitura por shift.

**Filtros temporais.** Hora (tratando janelas que cruzam a meia-noite), dia da
semana, dia do mês e mês por lista com intervalos (`"1,2,15-20,31"`), ano mínimo
e máximo, sessão com offset GMT do servidor, e blackout de datas. Tudo converge
numa função `IsTradingAllowed(datetime, string &motivo)` que **devolve o motivo
do bloqueio** — filtro que barra em silêncio é indistinguível de bug.

**Análise sobre o gráfico.** No desktop, hover abre mira e leitura da vela;
botão direito abre o menu de sobreposições, subpainéis e atalhos. No móvel, o
dedo percorre as velas e segurar abre a folha de ações.

**Varredura de mesas proprietárias.** 18 firmas com nota ponderada por critérios
que você escolhe, e a conta aberta de como cada nota foi formada.

**Diagnóstico de dados.** Testa ao vivo, dentro do navegador, quais APIs públicas
respondem — e lista as que foram testadas e reprovadas, com o motivo.

**Agente especialista.** [`.claude/agents/mesa-quant.md`](.claude/agents/mesa-quant.md)
define um agente do Claude Code que escreve, revisa e audita EAs, e fecha toda
entrega com a leitura de gestor: risco por operação, perda em dez derrotas
seguidas, expectativa matemática e custo de transação.

---

## Estrutura

```
├── index.html                  Painel de mesa
├── index-mobile.html           Painel móvel
├── IMPLANTACAO.md              Guia completo de implantação
├── build-mesas.py              Embute o levantamento de mesas no HTML
├── dados/
│   ├── mesas.json              Levantamento bruto, com fonte e data
│   └── mesas-normalizado.json  Campos numéricos comparáveis
├── mql5/MesaEA.mq5             Robô-base MetaTrader 5
├── mql4/MesaEA.mq4             Robô-base MetaTrader 4
└── .claude/agents/mesa-quant.md
```

O guia detalhado está em **[IMPLANTACAO.md](IMPLANTACAO.md)**.

---

## Dados

Cotações de cripto vêm da Binance, com Coinbase e Kraken de reserva. Câmbio
diário vem do Banco Central Europeu via Frankfurter. Todos os provedores são
públicos, sem chave, e foram verificados devolvendo cabeçalho de CORS.

Três coisas ditas com todas as letras:

- **Índices, ações e ouro não têm fonte gratuita viável** com CORS. Yahoo
  Finance, Stooq, FRED e exchangerate.host foram testados e reprovados. Esses
  instrumentos usam série sintética, claramente marcada na interface.
- **Câmbio diário é preço real, mas não é OHLC.** O BCE publica uma taxa de
  referência por dia útil; a máxima e a mínima da vela são derivadas.
- **O conteúdo editorial (notícias, assuntos quentes, vozes) é ilustrativo** e
  vem marcado como demonstração. Serve para provar o formato do painel. A seção
  6 do guia mostra como ligar uma fonte real.

---

## Sobre os dados de mesas proprietárias

São **regras publicadas pelas próprias firmas**, cada uma com link da fonte e a
data em que foi lida. Cada firma carrega um nível de confiança do dado, e onde as
fontes se contradisseram o conflito está registrado. Nenhum payout médio,
depoimento ou métrica de marketing entrou — esses números não são verificáveis.

A nota é um modelo de comparação desta ferramenta, **não um selo de qualidade**.
Ela pondera critérios que o usuário escolhe e mostra a conta.

Regras de mesa proprietária mudam sem aviso e sem retroatividade clara. A vida
mediana de uma firma do setor é de cerca de dois anos. **Confirme no site da
empresa antes de pagar qualquer taxa.**

---

## Antes de ligar um robô em conta real

- Backtest em "Cada tick com base em ticks reais", mínimo de dois anos.
- Uma rodada com spread aumentado — o backtest usa spread fixo, o mercado não.
- Forward test em demo por pelo menos um mês.
- Otimizar doze parâmetros em seis meses de dados produz uma curva linda e um
  robô morto.

Nada aqui é recomendação de investimento. É ferramenta. A decisão, o capital e a
consequência são de quem opera.

---

## Licença

MIT — veja [LICENSE](LICENSE).
