# Finanças (Fase 1) — Design

Registro de entradas/saídas via chat (texto ou áudio) no Slack, planilha Google Sheets como fonte de verdade. Canal dedicado `#hermes-financas` (já criado, bot convidado).

## Decisão: autenticação Google muda de service account para OAuth2

O doc de decisões (`hermes-agente-pessoal.md`) previa service account. O skill bundled `google-workspace` do Hermes (já sincronizado na instância) só suporta OAuth2 (fluxo de autorização pela conta pessoal do usuário via navegador, Desktop app credential do Google Cloud). Não existe caminho nativo para service account nesse skill, e escrever um script custom pra isso vai contra o princípio de menos-é-mais do projeto quando o nativo já resolve.

**Decisão**: usar OAuth2 via `google-workspace`. O doc de decisões deve ser atualizado para refletir essa mudança.

Escopo de autorização: `sheets` (não precisa de `gmail`, `calendar`, `drive`, `docs` — YAGNI, evita over-scoping o OAuth consent).

Token fica em `~/.hermes/google_token.json` dentro do container, que mapeia para `compose/hermes/data/google_token.json` no host — já coberto pelo `.gitignore` existente (`compose/*/data/*` exceto `config.yaml`).

## Planilha Google Sheets

Uma spreadsheet, três abas:

| Aba | Colunas | Papel |
|---|---|---|
| `lancamentos` | data, descricao, valor, categoria, tipo (entrada/saida) | Fonte de verdade dos movimentos. Uma linha por lançamento confirmado. |
| `recorrentes` | descricao, valor, dia_do_mes | Referência de despesas/receitas recorrentes. Não gera lançamento sozinho. |
| `saldo` | saldo_inicial (célula fixa), saldo_atual (fórmula) | `saldo_atual` = `saldo_inicial + SUMIF(lancamentos, tipo=entrada) - SUMIF(lancamentos, tipo=saida)`. Cálculo nativo do Sheets — o agente nunca escreve nessa aba, só lê pra responder "quanto tenho". |

A spreadsheet é criada manualmente pelo usuário (ou via `$GAPI sheets create` numa sessão de setup), e o ID é registrado no skill customizado (não é segredo — um ID de planilha sozinho não dá acesso a ninguém sem a própria autorização OAuth do usuário).

## Skill customizado `financas`

Novo `SKILL.md`, **versionado no repo** (declarativo, ao contrário de `data/` que é estado mutável e gitignored):

```
compose/hermes/custom-skills/financas/SKILL.md
```

Montado no container via bind mount adicional no `docker-compose.yml`, e registrado no `config.yaml`:

```yaml
skills:
  external_dirs:
    - /opt/custom-skills
```

O `SKILL.md` documenta: ID da planilha, layout exato das 3 abas, e as regras de comportamento:

- Mensagem em `#hermes-financas` que descreve um gasto/receita (texto ou áudio transcrito) → extrai valor, descrição, categoria, tipo → confirma com o usuário antes de gravar (mostra o que vai escrever) → `$GAPI sheets append` na aba `lancamentos`.
- Pergunta sobre saldo/gastos → lê a aba relevante com `$GAPI sheets get` e responde.
- Usuário descreve algo como recorrente ("aluguel 1500 todo dia 5") → grava em `recorrentes` (não em `lancamentos`).
- Nunca escreve na aba `saldo`.

Reaproveita o skill `google-workspace` como backend de execução (mesmo padrão de composição de skills que o projeto já usa — ver `related_skills` nos skills bundled).

## Recorrentes → lembrete via cron

Cron nativo do Hermes (já citado no banner do gateway: "Messaging platforms + cron scheduler") roda no dia registrado em `recorrentes` e posta em `#hermes-financas` perguntando se o pagamento aconteceu. Lançamento em `lancamentos` só acontece com confirmação explícita do usuário na resposta — nunca automático, pra não registrar um pagamento que atrasou ou falhou.

## Áudio: faster-whisper local

Confirmado por teste direto no container rodando: `faster_whisper` **não está instalado** na imagem oficial (`ModuleNotFoundError`). É preciso uma imagem derivada:

```dockerfile
# compose/hermes/Dockerfile
FROM nousresearch/hermes-agent:latest
USER root
RUN /opt/hermes/.venv/bin/pip install faster-whisper
USER hermes
```

`docker-compose.yml` do serviço `hermes` troca `image: nousresearch/hermes-agent:latest` por `build: .` (contexto = `compose/hermes/`), mantendo o padrão de composição por serviço já estabelecido no repo (`compose/docker-compose.yml` com `include`).

`config.yaml` ganha (ou confirma) `stt.provider: local` — já é o default documentado, sem necessidade de API key.

## Fora de escopo (YAGNI)

| Descartado | Motivo |
|---|---|
| Classificador de intenção próprio (é isso um lançamento?) | Canal dedicado já isola o contexto — toda mensagem em `#hermes-financas` é sobre finanças. O LLM interpreta linguagem natural nativamente, não precisa de camada extra. |
| Auto-lançamento de recorrentes | Risco de registrar pagamento que não aconteceu (atraso, falha de cobrança). Confirmação manual é mais simples e mais correta. |
| Categorização automática por ML/regras fixas | O próprio modelo já infere categoria a partir da descrição em linguagem natural; não precisa de taxonomia hardcoded nem sistema de regras. |
| Dashboard/relatório separado | Google Sheets já dá visualização direta — é exatamente por isso que o doc original descartou SQLite local. |

## Testes / verificação

Sem test suite tradicional (não é código de aplicação — é config + skill em markdown + planilha). Verificação é funcional, ponta a ponta:

1. Autorizar OAuth2, `$GSETUP --check` retorna `AUTHENTICATED`.
2. Criar a spreadsheet, anotar o ID no `SKILL.md`.
3. Rebuild da imagem com faster-whisper, subir o compose.
4. Mensagem de texto em `#hermes-financas` ("gastei 50 no mercado") → confirma → aparece linha em `lancamentos`.
5. Mensagem de áudio equivalente → mesmo resultado.
6. "quanto tenho de saldo?" → responde lendo a aba `saldo`.
7. "aluguel 1500 todo dia 5" → aparece em `recorrentes`, não em `lancamentos`.
8. Aguardar (ou simular) o cron do dia 5 → lembrete chega no canal → confirma → só aí aparece em `lancamentos`.
