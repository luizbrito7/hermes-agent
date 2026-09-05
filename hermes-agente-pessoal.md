# Agente Pessoal (Hermes) - Decisões

Documento de contexto para implementação. Princípio: YAGNI. Só entra o que resolve o problema atual.

## Objetivo

Agente de IA self-hosted para automatizar rotinas pessoais, acessível por chat e áudio.

## Stack

| Camada | Decisão |
|---|---|
| Agente | Hermes Agent (Nous Research), open source, self-hosted |
| Canal | Slack (Socket Mode, free tier) |
| LLM | NVIDIA NIM (`build.nvidia.com`), free tier, endpoint compatível com OpenAI |
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
- Acesso via service account.

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
| Modelo local (Ollama) | NVIDIA free tier (40 RPM) cobre o volume sem custo de hardware. |

## Pontos de atenção

- NVIDIA free tier: limite de 40 requisições por minuto. Folgado para o volume previsto, mas o free tier pode mudar.
- Slack free tier: histórico visível de 90 dias. Irrelevante, já que o Hermes tem memória própria.
- Áudio: transcrição via `faster-whisper` local ou gateway da Nous. Definir na Fase 1.
- Credenciais (token Slack, chave NVIDIA, service account do Google) fora do repositório.

## Próximo passo

Fase 1, etapa de infra: Terraform da VM Azure com state no HCP, cloud-init subindo Docker e Hermes, validação do agente pelo CLI antes de conectar o Slack.
