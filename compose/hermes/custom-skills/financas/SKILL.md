---
name: financas
description: "Registra e consulta finanças pessoais no Google Sheets"
version: 1.0.0
author: luizbrito7
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Finance, Sheets, Slack]
    related_skills: [google-workspace]
---

# Finanças

Registra entradas/saídas em `#hermes-financas` numa planilha Google Sheets, usando o skill `google-workspace` (OAuth2) como backend de execução.

Spreadsheet ID: `1aG2HwBcwWhWTf_lAT-4Gij-njB3EGoxsJ-mrMxyV7Sw`

## Abas e colunas

| Aba | Colunas (na ordem) |
|---|---|
| `lancamentos` | data, descricao, valor, categoria, tipo (`entrada` ou `saida`) |
| `recorrentes` | descricao, valor, dia_do_mes |
| `saldo` | só leitura — `B1` é o saldo inicial, `B2` é a fórmula de saldo atual. Nunca escrever aqui. |

## Regras

1. **Mensagem em `#hermes-financas` descrevendo um gasto ou receita** (texto ou áudio já transcrito): extrair `descricao`, `valor`, `categoria` (inferida da descrição, texto livre — sem lista fixa) e `tipo` (`entrada` ou `saida`). Se o usuário não mencionar uma data específica, use a data de hoje — **nunca adivinhe ou infira a data**; rode `date +%F` no terminal pra pegar a data real do sistema antes de montar o valor de `data`. Mostrar pro usuário exatamente o que vai gravar (incluindo a data) e pedir confirmação antes de escrever. Só depois da confirmação, rodar:

   ```bash
   python /opt/data/skills/productivity/google-workspace/scripts/google_api.py sheets append 1aG2HwBcwWhWTf_lAT-4Gij-njB3EGoxsJ-mrMxyV7Sw "lancamentos!A:E" --values '[["<data>","<descricao>","<valor>","<categoria>","<tipo>"]]'
   ```

2. **Pergunta sobre saldo** ("quanto tenho", "qual meu saldo"): ler a aba `saldo` e responder com o valor de `B2`.

   ```bash
   python /opt/data/skills/productivity/google-workspace/scripts/google_api.py sheets get 1aG2HwBcwWhWTf_lAT-4Gij-njB3EGoxsJ-mrMxyV7Sw "saldo!A1:B2"
   ```

3. **Pergunta sobre gastos** ("quanto gastei esse mês", "meus gastos com mercado"): ler a aba `lancamentos` e filtrar/somar na resposta (a leitura retorna todas as linhas — filtrar em texto, não existe query server-side no Sheets via este wrapper).

   ```bash
   python /opt/data/skills/productivity/google-workspace/scripts/google_api.py sheets get 1aG2HwBcwWhWTf_lAT-4Gij-njB3EGoxsJ-mrMxyV7Sw "lancamentos!A:E"
   ```

4. **Usuário descreve algo como recorrente** ("aluguel 1500 todo dia 5", "netflix 55 todo mês dia 10"): extrair `descricao`, `valor`, `dia_do_mes`, confirmar, e gravar em `recorrentes` — **nunca** em `lancamentos`:

   ```bash
   python /opt/data/skills/productivity/google-workspace/scripts/google_api.py sheets append 1aG2HwBcwWhWTf_lAT-4Gij-njB3EGoxsJ-mrMxyV7Sw "recorrentes!A:C" --values '[["<descricao>","<valor>","<dia_do_mes>"]]'
   ```

5. **Nunca escrever na aba `saldo`** — ela só tem fórmula, calculada pelo próprio Sheets.

6. **Nunca gravar em `lancamentos` sem confirmação explícita do usuário na mesma conversa.**
