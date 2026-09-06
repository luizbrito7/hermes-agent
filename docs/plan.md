# Agente Pessoal (Hermes) - Decisões

Documento de contexto para implementação. Princípio: YAGNI. Só entra o que resolve o problema atual.

## Objetivo

Agente de IA self-hosted para automatizar rotinas pessoais, acessível por chat e áudio.

## Stack

| Camada | Decisão |
|---|---|
| Agente | Hermes Agent (Nous Research), open source, self-hosted |
| Canal | Slack (Socket Mode, free tier) |
| LLM | Google Gemini (`gemini-flash-lite-latest`), free tier — trocado de NVIDIA NIM por latência alta |
| Runtime | Docker |
| Infra | VM na Azure (créditos existentes) |
| IaC | Terraform, state no HCP Terraform |
| Config interna | cloud-init ou Ansible |
| Dados financeiros | Google Sheets |

## Arquitetura

Duas camadas separadas, para que a troca de cloud provider não toque no que roda dentro da VM:

1. **Infra (Terraform):** VM, rede, disco, DNS. Módulo por provider. Trocar de nuvem = trocar o módulo.
2. **Runtime (cloud-init / Ansible):** Docker, Hermes, config, credenciais. Independente de provider.

State remoto no HCP Terraform desde o dia um (locking e histórico sem manter bucket).

## Fases

### Fase 1: Finanças
- Saldo inicial informado manualmente.
- Registro de entradas e saídas via chat no Slack (texto ou áudio).
- Acompanhamento de gastos e recorrências dentro do mês.
- Planilha no Google Sheets: abas de lançamentos, recorrentes e saldo.
- Acesso via OAuth2 (skill `google-workspace` do Hermes) — não service account: o skill nativo não suporta service account, e escrever um script custom pra isso ia contra o princípio de menos-é-mais.

### Fase 2: Agenda
- Blocos recorrentes de treino e estudo no Google Calendar.
- Prazos da FIAP cadastrados com antecedência.

### Fase 3: Busca de vagas
- Varredura em horário fixo, entrega no Slack.
- Triagem assistida em vez de checagem diária manual.

### Transversal
- Briefing matinal consolidado (agenda do dia, vagas novas, resumo financeiro) em uma única mensagem, via cron do Hermes.
- Lembretes dos marcos de obra e financiamento do apartamento.

## Fora de escopo (decidido)

| Descartado | Motivo |
|---|---|
| Open Finance / integração direta com bancos | Barreira regulatória: exige instituição autorizada pelo BACEN. Agregador (Pluggy, Belvo) é pago. Lançamento manual resolve. |
| WhatsApp Cloud API (Meta) | Burocracia: verificação de negócio, número dedicado, janela de 24h. |
| WhatsApp via Baileys | Não oficial, risco de ban. Slack cobre o caso de uso. |
| SQLite local para finanças | Sheets dá visibilidade direta sem depender do agente para consultar. |
| Modelo local (Ollama) | Free tier de LLM em nuvem (Gemini) cobre o volume sem custo de hardware. |

## Pontos de atenção

- Gemini free tier: ~15-30 RPM e ~1000 requisições/dia dependendo do modelo. Folgado para o volume previsto, mas o free tier pode mudar.
- Slack free tier: histórico visível de 90 dias. Irrelevante, já que o Hermes tem memória própria.
- Áudio: `faster-whisper` local (decidido) — precisa de imagem Docker derivada, não vem instalado na imagem oficial.
- Credenciais (tokens Slack, chave Gemini, client secret + token OAuth do Google) fora do repositório.

## Próximo passo

Infra e runtime da Fase 1 concluídos: VM Azure via Terraform, Hermes rodando em Docker Compose, conectado ao Slack, validado via CLI antes do Slack. Em andamento: feature de Finanças (skill customizado, planilha, OAuth2 do Google já autorizado) — ver `docs/superpowers/plans/2026-09-05-financas-implementation.md`.
