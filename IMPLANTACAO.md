# MESA — Guia de Implantação

Mesa de Operações Algorítmica: painel web de comando + agente especialista em
MQL4/MQL5 + robôs-base compiláveis.

---

## 1. O que existe neste repositório

```
Binance/
├── index.html                    Painel de mesa. Abre sem servidor, sem build.
├── index-mobile.html             Versão para o polegar: gestos, modos, blocos.
├── IMPLANTACAO.md                Este arquivo.
├── build-mesas.py                Embute o levantamento de mesas no index.html.
├── dados/
│   ├── mesas.json                Levantamento bruto: 18 mesas, 19 alertas, com fonte.
│   └── mesas-normalizado.json    Mesmo conteúdo com campos numéricos comparáveis.
├── .claude/
│   └── agents/
│       └── mesa-quant.md         Agente: arquiteto de EA + gestor de finanças.
├── mql5/
│   └── MesaEA.mq5                Robô-base MetaTrader 5 — 1.929 linhas.
└── mql4/
    └── MesaEA.mq4                Robô-base MetaTrader 4 — 2.293 linhas.
```

Quatro peças que se conversam:

| Peça | Papel |
|------|-------|
| **Painel de mesa** (`index.html`) | Onde você lê o mercado, monta a estratégia e **gera o código** |
| **Painel móvel** (`index-mobile.html`) | O mesmo motor, com gestos e blocos — ver seção 11 |
| **Agente** (`mesa-quant`) | Onde o esqueleto gerado vira robô de produção |
| **Robôs** (`mql4/`, `mql5/`) | A referência já pronta, com a bateria completa de filtros |

---

## 2. Subir o painel

### 2.1 Local — o caminho mais curto

```bash
open index.html
```

É um arquivo único, sem dependências, sem build, sem `npm install`. Aberto por
`file://` ele já funciona: cotações da Binance, indicadores, gerador de código,
relógios, histórico, alertas.

### 2.2 Servidor local (recomendado)

Alguns navegadores restringem `fetch` a partir de `file://`. Se a fita de
cotações ficar em **modo demonstração** mesmo com internet, sirva por HTTP:

```bash
python3 -m http.server 8080
# depois: http://localhost:8080
```

### 2.3 Publicar

Qualquer host estático serve — é um HTML só.

```bash
# Netlify
npx netlify deploy --prod --dir .

# Vercel
npx vercel --prod

# GitHub Pages
git init && git add . && git commit -m "MESA v1"
git branch -M main && git remote add origin <seu-repo>
git push -u origin main
# Settings → Pages → Deploy from branch: main / root
```

**Antes de publicar num endereço público**, leia a seção 7 — o painel guarda
credenciais de alerta apenas em memória, mas um painel exposto é um mapa da sua
operação.

---

## 3. Como o painel está organizado

Nove abas, navegáveis pelo teclado. `/` foca a busca global de qualquer lugar,
`Esc` fecha o que estiver aberto.

### Painel
Patrimônio, resultado do dia, drawdown, fator de lucro, acerto e exposição.
**Multigráficos**: quatro instrumentos em candlestick com EMA 9/21, timeframe
sincronizado. **Motor de sinal**: medidor de −100 a +100 com os limiares de
compra e venda marcados, e a tabela de indicadores mostrando não só a leitura
bruta como **a contribuição ponderada de cada um** para o score. **Estado dos
filtros**: os sete filtros temporais avaliados contra o instante atual, cada um
com o que está configurado e o que está acontecendo.

#### Análise sobre o gráfico

**Passar o mouse** sobre qualquer gráfico abre a mira e uma leitura flutuante da
vela sob o cursor: OHLC, variação, volume, EMA 9/21/50, RSI, histograma do MACD,
ATR absoluto e percentual, posição no canal de Bollinger, ADX com +DI e −DI, e o
score daquela vela. Velas anteriores ao aquecimento dos indicadores aparecem como
`aquecendo` em vez de exibir número — a leitura não existe ali, e inventá-la
seria pior que omiti-la.

**Botão direito** sobre o gráfico abre o menu de análise:

| Ação | O que faz |
|------|-----------|
| Analisar esta vela | Manda a vela para o motor de sinal e mostra qual indicador mais pesou |
| Focar no motor de sinal | Aponta o painel de sinal para aquele instrumento |
| Copiar leitura | Leva a leitura completa da vela para a área de transferência |
| Médias, EMA 50, Bollinger | Liga e desliga sobreposições, por gráfico |
| Subpainel | RSI, MACD com histograma, ATR, ADX com DI, ou volume |
| Janela | 45, 90 ou 180 velas |
| Notícias / Histórico | Salta para a aba já filtrada por aquele instrumento |
| Gerar robô | Preenche o construtor com o instrumento e gera o código |

Cada gráfico guarda seus próprios ajustes — dá para deixar o BTC com MACD e o
EUR/USD com ADX ao mesmo tempo. A etiqueta no cabeçalho mostra o que está ligado.

### Robô
O construtor. Mandato → pesos da estratégia → gestão de risco → filtros
temporais → **código gerado**. Cada mudança de campo regenera a *leitura do
gestor*, que é onde o painel discorda de você quando os números pedem.

### Mercado
Notícias filtradas pelos instrumentos da carteira, assuntos quentes com
aquecimento em 24h, novidades da plataforma e o calendário de eventos. O botão
**Aplicar ao blackout** joga todas as datas de impacto médio ou alto direto no
filtro do robô — é a ponte entre "sei que tem payroll na sexta" e "o robô não
opera na sexta".

### Social
Sentimento por instrumento **cruzado com o seu posicionamento**. A métrica
*Divergência* conta quantas posições suas estão contra o consenso — que não é
necessariamente ruim, mas é sempre informação.

### Histórico
760 operações com busca por texto livre, segmento, instrumento, direção,
resultado, robô, intervalo de datas e **faixa de hora** (aceita `8-12,14-18`).
Toda coluna ordena. Estatísticas do recorte recalculadas ao vivo: resultado,
acerto, expectativa e fator de lucro. Exporta CSV.

### Relógios
Oito praças com indicador de expediente, barra de sobreposição de sessões em
24h GMT com a linha do agora, conversor de horário e — o mais útil — a tabela
**Janela do robô**, que traduz sua janela de negociação do horário do servidor
para cada praça.

### Alertas
Dez regras liga-desliga, quatro canais (push MetaTrader, Telegram, webhook do
agente, notificação do navegador), modelo de mensagem com variáveis, horário de
silêncio e teto de avisos por hora.

### Mesas
Varredura de 18 mesas proprietárias globais com nota ponderada pela **sua**
perspectiva — seis critérios com peso ajustável (custo, regras de risco, meta,
liberdade, saque, confiança). Ver seção 12.

### Dados
Diagnóstico ao vivo das conexões. Ver seção 6.1.

---

## 4. Gerar e instalar um robô

### 4.1 No painel

1. Aba **Robô**.
2. **Mandato**: nome, magic number, símbolo, timeframe, plataforma.
3. **Estratégia**: ajuste os pesos. Peso zero remove o indicador do motor.
4. **Gestão de risco**: risco por operação, stops em múltiplo de ATR, limites diários.
5. **Filtros temporais**: hora, dias da semana, dias do mês, meses, anos, sessão, blackout.
6. **Leia a leitura do gestor.** Se houver dois blocos vermelhos, o painel está
   dizendo que a configuração não se sustenta. Ele costuma ter razão.
7. **Gerar** → **Copiar** ou **Baixar**.

> O download sai como `.txt` porque o hospedeiro não aceita extensão `.mq5`.
> Renomeie para `.mq5` ou `.mq4` antes de compilar.

### 4.2 No MetaTrader

**MetaTrader 5**

1. `Arquivo → Abrir Pasta de Dados` → `MQL5/Experts/`
2. Copie o `.mq5` para lá.
3. No MetaEditor, abra e pressione **F7**. Deve compilar com 0 erros.
4. No terminal, `Ctrl+N` → Consultores → arraste para o gráfico.
5. Marque **Permitir negociação automática** na aba Comum.

**MetaTrader 4**

Mesmo fluxo, em `MQL4/Experts/`. Requer build 600 ou superior.

### 4.3 Validar antes de ligar em conta real

Este passo não é opcional.

- Testador de estratégia em **"Cada tick com base em ticks reais"** (MT5) ou
  **"Every tick"** (MT4). Nunca "Open prices only" para estratégia intrabar.
- Mínimo **dois anos** de dados.
- Rode uma vez com **spread aumentado** — o backtest usa spread fixo, o mercado não.
- **Forward test em demo** por pelo menos um mês antes de arriscar dinheiro.

---

## 5. Usar o agente `mesa-quant`

O painel gera o esqueleto. O agente produz a versão de produção: tratamento de
erro de corretora, casos de borda, e a leitura financeira que o gerador do
navegador não faz.

```bash
claude
```

```
> Use o agente mesa-quant: quero um EA MQL5 de reversão em EURUSD H1,
> só na sessão de Londres, com risco de 0,5% e stop de 1,5 ATR.
```

O agente vai levantar o mandato (sete perguntas, de uma vez), escrever o código
e **fechar com a leitura de gestor**: risco por operação, perda em dez derrotas
seguidas, expectativa matemática, custo de transação e alerta de correlação.

Ele também revisa código que já existe:

```
> Use o agente mesa-quant para revisar mql5/MesaEA.mq5 e apontar
> o que quebra em conta real mas passa no backtest.
```

O agente é definido em [.claude/agents/mesa-quant.md](.claude/agents/mesa-quant.md).
Edite o arquivo para ajustar o comportamento — ele é texto, não configuração.

---

## 6. Ligar dados reais

### 6.1 Cotações — já funcionam

Todos os provedores abaixo foram testados com `curl -H "Origin: http://localhost"`
e confirmados devolvendo `Access-Control-Allow-Origin`. Nenhum exige chave. A aba
**Dados** repete esse teste ao vivo, dentro do navegador, e mostra latência.

| Provedor | Cobre | Usado para |
|----------|-------|------------|
| **Binance** | Cripto, 15m a 1d | Fonte principal de candles |
| **Coinbase Exchange** | Cripto, granularidade fixa | Reserva quando a Binance falha |
| **Kraken** | Cripto, inclui 240 min | Reserva do 4h, que a Coinbase não tem |
| **Frankfurter (BCE)** | Câmbio, só diário | EUR/USD, GBP/USD, USD/JPY no 1d |
| **open.er-api** | Câmbio corrente | Verificação de conexão |
| **CoinGecko** | Capitalização e ranking | Verificação de conexão |
| **AwesomeAPI** | Câmbio com real | USD/BRL |
| **Banco Central (SGS)** | Séries oficiais BR | USD/BRL de referência, Selic, IPCA |

Três detalhes que custam tempo se você não souber:

- **A Binance devolve 451 em alguns países.** O painel tenta
  `api.binance.com` e, se levar 451, repete em `data-api.binance.vision` —
  mesmo formato, sem bloqueio geográfico.
- **A Coinbase não aceita granularidade de 4 horas.** Só 60, 300, 900, 3600,
  21600 e 86400 segundos. Por isso o 4h cai na Kraken, que aceita 240 minutos.
  A Coinbase também devolve `[tempo, mínima, máxima, abertura, fechamento,
  volume]` — mínima e máxima **antes** da abertura, diferente de todo mundo — e
  do mais recente para o mais antigo.
- **Use `api.frankfurter.dev/v1/`, não `.app`.** O domínio antigo responde 301
  para o novo, e o redirecionamento **não carrega cabeçalho de CORS** — o
  `fetch` morre no navegador sem mensagem útil.

**Câmbio diário é preço real, mas não é OHLC.** O BCE publica uma taxa de
referência por dia útil. O painel monta a vela com abertura igual ao fechamento
anterior. O fechamento é real; a máxima e a mínima são derivadas, não observadas.
Está assim documentado na aba Dados.

**Índices, ações e ouro não têm fonte gratuita viável.** Testado e descartado:
Yahoo Finance responde 429 e nunca mandou CORS; Stooq passou a exigir resolução
de desafio JavaScript; FRED devolve CSV sem cabeçalho de CORS; exchangerate.host
passou a exigir chave. Para US100, US500 e XAU o caminho realista é Twelve Data
com chave gratuita (800 requisições por dia, tem CORS e é a única fonte testada
com **candles intradiários reais de câmbio**) ou um proxy de uma linha no seu
servidor. A aba Dados lista cada rejeitada com o motivo.

**A série sintética é determinística**: mesma semente, mesmo desenho. As âncoras
de preço foram calibradas contra cotação real em 18/07/2026 e **envelhecem** —
reveja `SEED_PX` se o modo demonstração começar a exibir ordens de grandeza
estranhas. Ela existe para provar o formato do painel, não para embasar decisão.
Nunca opere por ela.

### 6.2 Notícias — precisam ser ligadas

O conteúdo editorial de `NEWS`, `HOT`, `VOICES` e `CALENDAR` em `index.html` é
**ilustrativo** e vem marcado com o selo `demo` na interface. Substitua pela
fonte real:

**Opção A — MCP Financial AI Agent**

O [Financial AI Agent](https://mcpmarket.com/server/financial-ai-agent) expõe
dados de mercado e notícias por Model Context Protocol. Registre-o no Claude
Code:

```json
// .mcp.json
{
  "mcpServers": {
    "financial-ai-agent": {
      "command": "npx",
      "args": ["-y", "@extrawest/financial-ai-agent-mcp"],
      "env": { "FINANCIAL_API_KEY": "sua-chave" }
    }
  }
}
```

Depois peça ao agente que puxe as manchetes e reescreva o array `NEWS`. Como o
servidor roda no seu ambiente e não no navegador, o painel consome o resultado
já embutido — sem chave exposta no front-end.

**Opção B — API REST direta**

Troque o array `NEWS` por um `fetch` no seu provedor. O contrato é:

```js
{ sym:"BTCUSDT", tone:1|0|-1, t:"manchete", x:"por que isso importa para a operação" }
```

Se fizer isso, **remova o selo `demo`** de `newsItem()` — ele só deve aparecer
enquanto o conteúdo for ilustrativo.

### 6.3 Histórico real

O array `TRADES` é gerado com semente fixa. Para usar suas operações de verdade:

1. No MetaTrader: `Histórico → clique direito → Relatório → CSV`.
2. Converta para o formato:

```js
{ id, open:Date, sym, label, seg, side:"COMPRA"|"VENDA", lots,
  entry, exit, pnl, r, bars, ea, why }
```

3. Substitua o corpo do IIFE de `TRADES`.

O campo `seg` é o que alimenta a busca por segmento. O campo `r` (resultado em
múltiplos de risco) é o que torna a expectativa comparável entre instrumentos —
não pule.

---

## 7. Notificações no celular

### Telegram — o caminho mais simples

1. Fale com `@BotFather` no Telegram → `/newbot` → guarde o token.
2. Adicione o bot a um grupo, ou mande `/start` no privado.
3. Descubra o chat ID:
   `https://api.telegram.org/bot<TOKEN>/getUpdates`
4. Aba **Alertas** → canal Telegram → token e chat ID → **Salvar canal**.

### Push nativo do MetaTrader

1. Instale o app MetaTrader no celular.
2. No app: `Configurações → Mensagens` → copie o **MetaQuotes ID**.
3. No terminal desktop: `Ferramentas → Opções → Notificações` → cole o ID → teste.
4. No EA, use `SendNotification("texto")`.

O `mesa-quant` adiciona os pontos de disparo no código se você pedir:

```
> Adicione SendNotification em: entrada, stop, limite diário e desconexão.
```

### Webhook do agente

Para o Claude Code entregar os alertas, aponte o canal para um endpoint seu e
agende uma rotina:

```
> /schedule a cada 15 minutos: leia o log do MetaTrader, e se houver
> stop acionado ou limite diário atingido, me notifique.
```

### O que fica guardado onde

Credenciais de alerta ficam **apenas em memória do navegador** — some ao
recarregar a página. Isso é proposital: um painel publicado não deve carregar
token de bot. Para operação de verdade, guarde as credenciais no lado do
servidor ou no próprio terminal MetaTrader, nunca no HTML.

---

## 8. Personalizar

| Quero mudar | Onde mexer em `index.html` |
|-------------|---------------------------|
| Instrumentos da carteira | `const BOOK` |
| Cores, tipografia, espaçamento | Bloco `:root` no `<style>` — tudo é token |
| Indicadores e pesos padrão | `S.weights` e `W_META` |
| Fórmula do score | `computeScore()` — e o espelho MQL em `genMQL5`/`genMQL4` |
| Praças e fusos | `const PLACES` |
| Janelas de sessão | `const SESSIONS` (horários em GMT) |
| Regras de alerta | `const RULES` |
| Robôs no histórico | `const EAS` |

> Se mudar a fórmula do score no painel, **mude também nos dois geradores**.
> Painel e robô contando histórias diferentes é a pior falha possível aqui:
> você toma decisão por uma leitura e o robô opera por outra.

O tema segue o sistema operacional e tem alternância manual no botão `◐`. Ambos
os temas são desenhados, não invertidos.

---

## 9. Diagnóstico

| Sintoma | Causa provável | Solução |
|---------|---------------|---------|
| Fita presa em "modo demonstração" | `fetch` bloqueado em `file://`, offline, ou CSP | Sirva por HTTP (seção 2.2) e abra a aba **Dados** |
| Só cripto ao vivo, câmbio sintético | Câmbio real só existe no timeframe 1d | Troque o timeframe para `1d` |
| Todos os provedores falham de uma vez | O bloqueio é do ambiente, não deles | Aba **Dados** → **Testar todas** diz qual erro é |
| Hover mostra "aquecendo" | Vela anterior ao aquecimento dos indicadores | Normal nas primeiras ~30 velas da janela |
| Gráficos em branco | Canvas com altura zero durante troca de aba | Clique em **Atualizar** |
| EA não compila | Arquivo salvo com extensão `.txt` | Renomeie para `.mq5`/`.mq4` |
| EA compila mas não opera | Negociação automática desligada | Botão "Algo Trading" no terminal |
| EA opera fora da janela | Offset GMT do servidor errado | Compare a hora do terminal com a sua e ajuste `OffsetGMT` |
| Nenhum trade no backtest | Filtro bloqueando em silêncio | Veja o painel do EA — ele imprime o motivo |
| Lote sempre no mínimo | Stop pequeno demais ou `TICK_VALUE` zerado | Verifique o símbolo nas especificações da corretora |
| Notificação não chega | Canal salvo mas credencial inválida | Teste o token direto na API do Telegram |

**Quando o filtro de sessão bloqueia tudo:** se `SessaoAlvo` estiver marcada e a
janela de horário não intersectar aquela sessão, nada passa. É a pegadinha de
configuração mais comum. A tabela *Janela do robô* na aba Relógios existe para
mostrar isso antes de você descobrir no backtest.

---

## 10. Riscos que este projeto não elimina

Escrito aqui porque software financeiro tende a esconder isso no rodapé.

- **Backtest não é promessa.** Otimizar 12 parâmetros em 6 meses de dados produz
  uma curva linda e um robô morto. O painel mostra a expectativa do histórico
  justamente para você comparar com o que a otimização prometeu.
- **Correlação some risco.** Risco de 1% em cinco pares correlacionados é risco
  de 5% numa aposta só. O painel avisa quando detecta concentração de segmento.
- **Custo mata estratégia lucrativa no papel.** Spread, comissão e swap
  multiplicados pela frequência aparecem na leitura do gestor. Olhe.
- **Dado sintético não é mercado.** O modo demonstração existe para provar o
  formato do painel. Decisão só sobre dado real.
- **A nota de uma mesa não é aval.** Ela pondera regras publicadas. Não mede
  solvência, não audita pagamento e não prevê encerramento — e o setor encerra
  empresas o tempo todo.
- **Nada aqui é recomendação de investimento.** É ferramenta. A decisão, o
  capital e a consequência são seus.

---

## 11. Versão móvel

`index-mobile.html` não é o painel de mesa espremido: é outra interface sobre o
mesmo motor. Os indicadores, os provedores de dados, os filtros temporais, os
geradores MQL5/MQL4 e os dados das mesas são **o mesmo código**, extraído de
`index.html` sem alteração. O que muda é tudo que se toca.

```bash
python3 -m http.server 8080
# no celular, na mesma rede: http://<ip-do-seu-mac>:8080/index-mobile.html
```

Descubra o IP com `ipconfig getifaddr en0`.

### O seletor de modo

A barra acima das abas decide **o que o arrastar faz**. É a resposta para o
conflito clássico do toque: deslizar não pode significar três coisas ao mesmo
tempo.

| Modo | Arrastar na tela | Arrastar no gráfico |
|------|-----------------|--------------------|
| **Navegar** | troca de seção | troca de seção |
| **Analisar** | troca de seção | percorre as velas |
| **Ajustar** | — | — (pega o bloco pela alça ⠿) |

### Gestos

- **Deslizar na horizontal** troca de seção, com resistência elástica nas pontas.
- **Puxar para baixo** no topo recarrega as cotações.
- **Segurar um gráfico** abre a folha de ações — o equivalente móvel do botão
  direito: sobreposições, subpainel, janela de velas e atalhos para notícias,
  histórico e gerador de robô daquele instrumento.
- **Pinçar** o gráfico alterna a janela entre 45, 90 e 180 velas.
- **Arrastar ⠿** no modo Ajustar reordena os blocos; **×** oculta.
- Cada gesto relevante devolve um toque no vibracall.

### Blocos

Toda seção é uma pilha de blocos reordenáveis. No modo **Ajustar**, arraste pela
alça para mudar a ordem e toque no × para ocultar. A disposição fica salva no
navegador — some se o armazenamento estiver bloqueado, e o painel continua
funcionando.

Na seção **Gráficos**, cada instrumento é um bloco: reordenar os blocos **é**
mover os gráficos. Blocos ocultos não somem — no modo Ajustar eles aparecem
esmaecidos com **+** para voltar, e o menu **Mais** tem "Restaurar blocos
ocultos".

### O que ficou diferente do painel de mesa

- **Quatro abas na barra + Mais**: Painel, Gráficos, Robô, Mesas. As outras seis
  (Mercado, Social, Histórico, Relógios, Alertas, Dados) ficam na folha do
  botão Mais e continuam acessíveis pelo deslize.
- **Tabelas viraram listas.** Ler doze colunas num celular é ficção; cada linha
  traz o essencial e abre a ficha completa numa folha inferior.
- **Sem hover.** Toda a leitura de vela do desktop virou a barra de leitura que
  aparece sob o gráfico enquanto o dedo percorre as velas.
- **Campos com fonte de 16px**, que é o limite abaixo do qual o iOS dá zoom
  automático ao focar um campo.
- **Respeita a área segura** do notch e da barra de gestos.

Os dois arquivos são independentes: editar um não mexe no outro. Se você alterar
a fórmula do score ou os geradores MQL, altere nos dois — ou reextraia o motor
com o mesmo procedimento e recoloque.

---

## 12. Varredura de mesas proprietárias

A aba **Mesas** compara 18 firmas globais. Ela existe porque a informação que
decide se você perde ou não o valor da avaliação — sobretudo **o tipo de
drawdown** — costuma estar enterrada no help center, e não na página de vendas.

### Como a nota é calculada

A nota **não é um selo de qualidade**. É uma média ponderada de seis critérios,
com pesos que você mexe nos controles à esquerda. Clicar em qualquer mesa abre a
ficha com **a conta aberta**: quanto cada critério pontuou, por quê, e com que
peso entrou.

| Critério | O que mede |
|----------|-----------|
| Custo | Taxa da avaliação de 100 mil e se ela é reembolsada |
| Regras de risco | Tipo de drawdown, teto total, limite diário |
| Meta de lucro | Soma das metas das fases |
| Liberdade | Notícias, overnight, fim de semana, prazo, regra de consistência |
| Saque | Divisão de lucro e prazo do primeiro pagamento |
| Confiança | Tempo de operação, bandeiras vermelhas, firmeza do próprio dado |

O peso padrão maior fica em **regras de risco** porque drawdown rastreável sobre
o pico é o que mais reprova trader competente. Mude se discordar — é o objetivo
dos controles.

### Programa de referência

Cada mesa vende vários produtos com regras diferentes. Comparar "a firma" seria
comparar coisas distintas, então a nota usa **um programa de referência por
mesa** — de preferência a avaliação de duas fases de 100 mil, ou a de uma fase
quando não existe a de duas. Firmas de futuros têm o drawdown em dólar convertido
para percentual (USD 3.000 em 100k = 3%). O programa escolhido aparece na ficha,
e o texto original de todos os produtos fica preservado nos campos descritivos.

### O que os dados são, e o que não são

- São **regras publicadas pelas próprias firmas**, com link da fonte e a data em
  que foram lidas — 19/07/2026.
- Cada mesa tem um campo `confiancaDado`: **alta** (help center oficial lido
  direto, 13 mesas), **média** (comparador ou trecho indexado, 4 mesas), **baixa**
  (fonte única ou conflitante, 1 mesa). Três sites bloquearam leitura automatizada.
- Onde as fontes se contradisseram, prevaleceu a oficial e o conflito ficou
  registrado nas observações. Onde nada era confiável, o campo ficou vazio em vez
  de receber um chute.
- **Não há nenhum valor de payout médio, depoimento ou métrica de marketing.**
  Esses números não são verificáveis e não entram.

O painel **Bandeiras** lista 19 registros de encerramentos, crises de pagamento,
processos e mudanças estruturais do setor, cada um com fonte — incluindo casos
recentes e graves. Leia essa lista antes da tabela de notas: uma mesa com nota
alta e bandeira vermelha continua sendo uma mesa com bandeira vermelha.

### Atualizar o levantamento

```bash
# 1. edite dados/mesas-normalizado.json
# 2. reembuta no painel
python3 build-mesas.py
```

Os dados são embutidos no HTML em vez de carregados por `fetch` porque a página
precisa funcionar por `file://` e publicada, onde requisição a arquivo local
falha. O script é idempotente: rode quantas vezes quiser.

Para uma revisão completa, peça ao agente:

```
> Use o agente mesa-quant para revisar dados/mesas-normalizado.json contra
> as fontes oficiais e me dizer o que mudou desde 19/07/2026.
```

> **A vida mediana de uma prop firm é de cerca de dois anos.** Entre um terço e
> metade das que existiam em 2024 já não operam. Trate qualquer levantamento
> deste setor como perecível, e confirme no site da empresa antes de pagar.

---

## 13. Próximos passos sugeridos

1. **Trocar as notícias por fonte real** (seção 6.2) — é o que mais aproxima o
   painel de uma mesa de verdade.
2. **Importar o histórico real** (seção 6.3) — as estatísticas só valem sobre as
   suas operações.
3. **Ligar cotações de câmbio e índices** de uma corretora com REST.
4. **Persistir configuração** em `localStorage` para o painel lembrar os
   parâmetros do robô entre sessões.
5. **Pedir ao `mesa-quant`** uma variante da estratégia por regime de
   volatilidade — o filtro de ATR já está lá, falta a lógica de troca.
