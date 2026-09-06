# Finanças (Fase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Registro e consulta de entradas/saídas pessoais via chat (texto/áudio) no Slack (`#hermes-financas`), com Google Sheets como fonte de verdade.

**Architecture:** Um skill customizado (`SKILL.md`) versionado no repo ensina o agente a usar o skill bundled `google-workspace` (OAuth2, não service account) pra ler/escrever numa planilha de 3 abas. Áudio via `faster-whisper` local, que exige uma imagem Docker derivada. Nenhum código de aplicação é escrito — tudo é config declarativa + markdown + planilha.

**Tech Stack:** Hermes Agent (Docker, `nousresearch/hermes-agent`), skill `google-workspace` (OAuth2 + `$GAPI` CLI), Google Sheets, `faster-whisper`, Slack Socket Mode.

**Spec:** `docs/superpowers/specs/2026-09-05-financas-design.md`

## Global Constraints

- YAGNI: sem classificador de intenção próprio, sem categorização por regras fixas, sem auto-lançamento de recorrentes, sem dashboard separado (ver spec, seção "Fora de escopo").
- Auth Google é **OAuth2** via `google-workspace` — não service account (decisão revertida do doc original).
- Tudo que é config/comportamento declarado fica versionado no repo; segredos e estado mutável (tokens, sessions, memórias) ficam em `compose/hermes/data/` (gitignored, exceto `config.yaml`).
- `HERMES_UID`/`HERMES_GID=1000` já alinhados com o host — não fazer `chown` manual pro usuário do host em `compose/hermes/data/` de novo (quebra o container).
- Todo commit passa pelo hook `gitleaks` (`.githooks/pre-commit`, já ativo).
- VM: `hermes@20.226.91.125`, chave `~/.ssh/hermes_vm`, repo clonado em `/opt/hermes/hermes-agent`. Deploy = `git pull` na VM + `docker compose -f compose/docker-compose.yml up -d`.
- Escopo OAuth: só `sheets` (nem `gmail`, `calendar`, `drive`, `docs`).
- Commits terminam com `Claude-Session: https://claude.ai/code/session_019oprrzCpWHbdKnxZrKcDgu`.

---

### Task 1: Autorizar Google Workspace (OAuth2) e criar a spreadsheet

**Files:**
- Modify: `docs/plan.md` (atualiza decisão de service account → OAuth2)

**Interfaces:**
- Produces: token OAuth em `~/.hermes/google_token.json` dentro do container (persistido em `compose/hermes/data/google_token.json` no host, gitignored). ID da spreadsheet (string, ex.: `1a2B3c...`) — usado pela Task 2.

- [ ] **Step 1: Checar se já tem client OAuth configurado**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/setup.py --check"
```

Esperado: `NOT_AUTHENTICATED` (primeira vez).

- [ ] **Step 2: Criar o client OAuth no Google Cloud Console (ação manual do usuário)**

Passos que o usuário precisa fazer (guiar em tempo real, não dá pra automatizar — exige navegador e login do usuário):

1. https://console.cloud.google.com/projectselector2/home/dashboard — criar/selecionar um projeto.
2. https://console.cloud.google.com/apis/library — habilitar **Google Sheets API**.
3. https://console.cloud.google.com/apis/credentials — Create Credentials → OAuth 2.0 Client ID → tipo **Desktop app**.
4. Se o app estiver em modo "Testing": https://console.cloud.google.com/auth/audience → Test users → adicionar o email do usuário.
5. Baixar o JSON do client e enviar o caminho local do arquivo.

- [ ] **Step 3: Registrar o client secret no container**

Copiar o JSON baixado pra dentro do volume montado e rodar o setup (caminho local do JSON varia por usuário — pedir no chat):

```bash
scp -i ~/.ssh/hermes_vm <caminho_local_do_json> hermes@20.226.91.125:/tmp/gws-client-secret.json
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker cp /tmp/gws-client-secret.json hermes:/tmp/gws-client-secret.json && docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/setup.py --client-secret /tmp/gws-client-secret.json && rm /tmp/gws-client-secret.json"
```

- [ ] **Step 4: Gerar URL de autorização (escopo só `sheets`)**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/setup.py --auth-url --services sheets --format json"
```

Extrair o campo `auth_url` da resposta, mandar pro usuário abrir no navegador, autorizar, e copiar a URL de redirect completa (vai falhar em `localhost` — isso é esperado, só copiar a URL da barra de endereço mesmo assim).

- [ ] **Step 5: Trocar o código pela credencial**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/setup.py --auth-code 'URL_OU_CODIGO_COLADO_PELO_USUARIO' --format json"
```

- [ ] **Step 6: Confirmar autenticação**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/setup.py --check"
```

Esperado: `AUTHENTICATED`.

- [ ] **Step 7: Criar a spreadsheet com as 3 abas**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets create --title 'Financas Hermes' --sheet-name 'lancamentos'"
```

Anotar o `spreadsheetId` do JSON retornado. Depois, adicionar as outras duas abas — o comando `sheets create` só cria uma; usar a API do Sheets pra `batchUpdate` não é exposto pelo wrapper, então criar `recorrentes` e `saldo` manualmente pela UI do Sheets (abrir o link `spreadsheetUrl` retornado, botão "+" no rodapé, renomear aba) é mais simples que contornar o wrapper — YAGNI, é uma ação de 30 segundos feita uma vez.

- [ ] **Step 8: Preencher cabeçalhos e fórmula de saldo**

```bash
SHEET_ID="<spreadsheetId do Step 7>"
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets update $SHEET_ID 'lancamentos!A1:E1' --values '[[\"data\",\"descricao\",\"valor\",\"categoria\",\"tipo\"]]'"
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets update $SHEET_ID 'recorrentes!A1:C1' --values '[[\"descricao\",\"valor\",\"dia_do_mes\"]]'"
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets update $SHEET_ID 'saldo!A1:B2' --values '[[\"saldo_inicial\",0],[\"saldo_atual\",\"=A2+SUMIF(lancamentos!E:E,\\\"entrada\\\",lancamentos!C:C)-SUMIF(lancamentos!E:E,\\\"saida\\\",lancamentos!C:C)\"]]'"
```

Ajustar `saldo_inicial` (célula `B1`) pro valor real informado pelo usuário.

- [ ] **Step 9: Atualizar `docs/plan.md` com a decisão de auth**

Editar a linha da tabela "Pontos de atenção" ou a seção de Fase 1 em `docs/plan.md`, trocando a menção a service account por:

```markdown
- Finanças: acesso ao Google Sheets via OAuth2 (skill `google-workspace` do Hermes), não service account — o skill nativo não suporta service account, e escrever um script custom pra isso ia contra o princípio de menos-é-mais.
```

- [ ] **Step 10: Commit**

```bash
cd ~/projects/pessoal/hermes-agent
git add docs/plan.md
git commit -m "$(cat <<'EOF'
docs: atualiza doc de decisões — auth Google via OAuth2, não service account

Claude-Session: https://claude.ai/code/session_019oprrzCpWHbdKnxZrKcDgu
EOF
)"
git push
```

---

### Task 2: Skill customizado `financas`

**Files:**
- Create: `compose/hermes/custom-skills/financas/SKILL.md`

**Interfaces:**
- Consumes: `spreadsheetId` da Task 1 Step 7.
- Produces: skill `financas` — carrega via `/financas` ou por relevância de conversa, ensina o agente a ler/escrever na spreadsheet via `$GAPI` (do skill `google-workspace`).

- [ ] **Step 1: Criar o diretório e o SKILL.md**

```bash
mkdir -p ~/projects/pessoal/hermes-agent/compose/hermes/custom-skills/financas
```

Conteúdo de `compose/hermes/custom-skills/financas/SKILL.md` (substituir `SPREADSHEET_ID_AQUI` pelo ID real da Task 1 Step 7):

```markdown
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

Spreadsheet ID: `SPREADSHEET_ID_AQUI`

## Abas e colunas

| Aba | Colunas (na ordem) |
|---|---|
| `lancamentos` | data, descricao, valor, categoria, tipo (`entrada` ou `saida`) |
| `recorrentes` | descricao, valor, dia_do_mes |
| `saldo` | só leitura — `A2` é o saldo inicial, `B2` é a fórmula de saldo atual. Nunca escrever aqui. |

## Regras

1. **Mensagem em `#hermes-financas` descrevendo um gasto ou receita** (texto ou áudio já transcrito): extrair `data` (default: hoje), `descricao`, `valor`, `categoria` (inferida da descrição, texto livre — sem lista fixa) e `tipo` (`entrada` ou `saida`). Mostrar pro usuário exatamente o que vai gravar e pedir confirmação antes de escrever. Só depois da confirmação, rodar:

   ```bash
   python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets append SPREADSHEET_ID_AQUI "lancamentos!A:E" --values '[["<data>","<descricao>","<valor>","<categoria>","<tipo>"]]'
   ```

2. **Pergunta sobre saldo** ("quanto tenho", "qual meu saldo"): ler a aba `saldo` e responder com o valor de `B2`.

   ```bash
   python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets get SPREADSHEET_ID_AQUI "saldo!A1:B2"
   ```

3. **Pergunta sobre gastos** ("quanto gastei esse mês", "meus gastos com mercado"): ler a aba `lancamentos` e filtrar/somar na resposta (a leitura retorna todas as linhas — filtrar em texto, não existe query server-side no Sheets via este wrapper).

   ```bash
   python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets get SPREADSHEET_ID_AQUI "lancamentos!A:E"
   ```

4. **Usuário descreve algo como recorrente** ("aluguel 1500 todo dia 5", "netflix 55 todo mês dia 10"): extrair `descricao`, `valor`, `dia_do_mes`, confirmar, e gravar em `recorrentes` — **nunca** em `lancamentos`:

   ```bash
   python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets append SPREADSHEET_ID_AQUI "recorrentes!A:C" --values '[["<descricao>","<valor>","<dia_do_mes>"]]'
   ```

5. **Nunca escrever na aba `saldo`** — ela só tem fórmula, calculada pelo próprio Sheets.

6. **Nunca gravar em `lancamentos` sem confirmação explícita do usuário na mesma conversa.**
```

- [ ] **Step 2: Commit**

```bash
cd ~/projects/pessoal/hermes-agent
git add compose/hermes/custom-skills/financas/SKILL.md
git commit -m "$(cat <<'EOF'
feat: skill customizado financas — registro/consulta no Google Sheets

Claude-Session: https://claude.ai/code/session_019oprrzCpWHbdKnxZrKcDgu
EOF
)"
git push
```

---

### Task 3: Plugar o skill customizado no container

**Files:**
- Modify: `compose/hermes/data/config.yaml`
- Modify: `compose/hermes/docker-compose.yml`

**Interfaces:**
- Consumes: `compose/hermes/custom-skills/financas/` da Task 2.
- Produces: skill `financas` visível dentro do container em `/opt/custom-skills/financas/`, listado em `skills_list` e disponível como `/financas`.

- [ ] **Step 1: Adicionar o bind mount no `docker-compose.yml`**

Editar `compose/hermes/docker-compose.yml`, adicionando a linha de volume (mantendo o que já existe):

```yaml
    volumes:
      - ./data:/opt/data
      - ./custom-skills:/opt/custom-skills:ro
```

- [ ] **Step 2: Registrar `external_dirs` no `config.yaml`**

Editar `compose/hermes/data/config.yaml`, adicionando (sem remover nada do que já existe — `model:`, `plugins:`, `_config_version:`, `platforms:`):

```yaml
skills:
  external_dirs:
    - /opt/custom-skills
```

- [ ] **Step 3: Commit**

```bash
cd ~/projects/pessoal/hermes-agent
git add compose/hermes/docker-compose.yml compose/hermes/data/config.yaml
git commit -m "$(cat <<'EOF'
feat: plugar skill financas via skills.external_dirs

Claude-Session: https://claude.ai/code/session_019oprrzCpWHbdKnxZrKcDgu
EOF
)"
git push
```

- [ ] **Step 4: Deploy e verificação**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "cd /opt/hermes/hermes-agent && git pull && docker compose -f compose/docker-compose.yml up -d && sleep 8 && docker exec hermes hermes skills list 2>&1 | grep -i financas"
```

Esperado: linha mostrando o skill `financas` carregado.

---

### Task 4: Áudio — imagem Docker derivada com `faster-whisper`

**Files:**
- Create: `compose/hermes/Dockerfile`
- Modify: `compose/hermes/docker-compose.yml`
- Modify: `compose/hermes/data/config.yaml`

**Interfaces:**
- Produces: imagem `hermes-agent-financas:latest` local, com `faster_whisper` importável no venv do container. `stt.provider: local` ativo.

- [ ] **Step 1: Criar o Dockerfile**

`compose/hermes/Dockerfile`:

```dockerfile
FROM nousresearch/hermes-agent:latest
USER root
RUN /opt/hermes/.venv/bin/pip install faster-whisper
USER hermes
```

- [ ] **Step 2: Trocar `image:` por `build:` no compose**

Editar `compose/hermes/docker-compose.yml` — a seção `hermes:` fica:

```yaml
services:
  hermes:
    build: .
    image: hermes-agent-financas:latest
    container_name: hermes
    restart: unless-stopped
    command: gateway run
    volumes:
      - ./data:/opt/data
      - ./custom-skills:/opt/custom-skills:ro
    env_file:
      - .env
    environment:
      - HERMES_UID=${HERMES_UID:-1000}
      - HERMES_GID=${HERMES_GID:-1000}
```

- [ ] **Step 3: Configurar `stt.provider` no `config.yaml`**

Adicionar em `compose/hermes/data/config.yaml`:

```yaml
stt:
  provider: local
```

- [ ] **Step 4: Commit**

```bash
cd ~/projects/pessoal/hermes-agent
git add compose/hermes/Dockerfile compose/hermes/docker-compose.yml compose/hermes/data/config.yaml
git commit -m "$(cat <<'EOF'
feat: imagem derivada com faster-whisper pra transcrição de áudio local

Claude-Session: https://claude.ai/code/session_019oprrzCpWHbdKnxZrKcDgu
EOF
)"
git push
```

- [ ] **Step 5: Deploy (build na VM) e verificação**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "cd /opt/hermes/hermes-agent && git pull && docker compose -f compose/docker-compose.yml build && docker compose -f compose/docker-compose.yml up -d && sleep 8 && docker exec hermes /opt/hermes/.venv/bin/python -c 'import faster_whisper; print(\"ok\")'"
```

Esperado: `ok` (sem `ModuleNotFoundError`).

---

### Task 5: Verificação ponta a ponta

**Files:** nenhum (só validação funcional via Slack + SSH).

**Interfaces:**
- Consumes: tudo das Tasks 1-4.

- [ ] **Step 1: Confirmar container saudável**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker ps --filter name=hermes --format '{{.Status}}' && docker logs hermes --tail 20"
```

Esperado: `Up`, sem `PermissionError` ou `ModuleNotFoundError` nos logs.

- [ ] **Step 2: Lançamento por texto**

No Slack, em `#hermes-financas`, mandar: `gastei 50 no mercado hoje`. Confirmar quando o agente perguntar. Verificar a linha nova:

```bash
SHEET_ID="<spreadsheetId>"
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets get $SHEET_ID 'lancamentos!A:E'"
```

Esperado: nova linha com `saida`, valor `50`, categoria plausível (ex. "mercado" ou "alimentação").

- [ ] **Step 3: Lançamento por áudio**

Mandar um áudio no mesmo canal dizendo algo equivalente ("recebi 200 de freelance"). Confirmar. Repetir o comando do Step 2 e checar a linha `entrada` correspondente.

- [ ] **Step 4: Consulta de saldo**

Mandar `quanto tenho de saldo?`. Esperado: o agente responde com o valor de `saldo!B2`, batendo com:

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets get $SHEET_ID 'saldo!A1:B2'"
```

- [ ] **Step 5: Registro de recorrente**

Mandar `aluguel 1500 todo dia 5`. Confirmar. Checar que caiu em `recorrentes`, não em `lancamentos`:

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes python /opt/hermes/skills/productivity/google-workspace/scripts/google_api.py sheets get $SHEET_ID 'recorrentes!A:C'"
```

- [ ] **Step 6: Simular o lembrete de recorrente (sem esperar o dia real)**

Criar um cron job de teste e disparar na hora, pra não depender de esperar até o dia 5:

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes hermes cron create 'in 1 day' 'Pergunte no canal se o aluguel de 1500 foi pago hoje, e se sim registre em lancamentos com skill financas' --skill financas"
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes hermes cron list"
```

Anotar o `job_id` retornado e disparar manualmente:

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes hermes cron run <job_id>"
```

Esperado: mensagem chega em `#hermes-financas` perguntando sobre o pagamento. Responder "sim, paguei" e confirmar que **só agora** aparece uma linha em `lancamentos` (não antes, no Step 5).

- [ ] **Step 7: Remover o cron job de teste**

```bash
ssh -i ~/.ssh/hermes_vm hermes@20.226.91.125 "docker exec hermes hermes cron remove <job_id>"
```

- [ ] **Step 8: Confirmar que a aba `saldo` nunca foi escrita pelo agente**

Revisão manual: nenhum dos steps acima chamou `sheets update`/`sheets append` na aba `saldo` — só `sheets get`. Nada a rodar, é checklist de revisão do que já foi feito.

---

## Self-Review

**Cobertura do spec:** auth OAuth2 (Task 1), planilha 3 abas + fórmula de saldo (Task 1), skill customizado (Task 2), `skills.external_dirs` (Task 3), recorrentes só como referência + lembrete via cron sem auto-lançamento (Task 5 Step 6), faster-whisper (Task 4), fora-de-escopo (nenhuma task implementa classificador/dashboard/auto-lançamento — correto, é pra não implementar mesmo). Doc de decisões atualizado (Task 1 Step 9).

**Placeholders:** `SPREADSHEET_ID_AQUI` no SKILL.md é substituído por um valor real na própria Task 2 Step 1, usando o ID capturado na Task 1 — não é um placeholder deixado pro futuro, é uma substituição de texto que acontece dentro do mesmo plano. `<job_id>` e `<spreadsheetId>` nos comandos de shell são valores capturados no step anterior, não lacunas.

**Consistência:** nome do skill (`financas`) e caminho (`/opt/custom-skills/financas`) consistentes entre Task 2 e Task 3. Nome do container (`hermes`) e do arquivo compose (`compose/docker-compose.yml`, via `include: hermes/docker-compose.yml`) consistentes com o que já está rodando na VM.
