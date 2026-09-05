<h1 align="center">
  hermes-agent
</h1>

<p align="center">
  <img src="docs/icon-agent.png" alt="Hermes" width="120" />
</p>

<p align="center">
  <img src="https://skillicons.dev/icons?i=docker,azure,terraform,git,github,linux,python,bash" alt="Stacks" />
</p>

Agente pessoal self-hosted ([Hermes Agent](https://github.com/NousResearch/hermes-agent), Nous Research) rodando numa VM Azure, acessível via Slack. Contexto completo das decisões em [`docs/plan.md`](docs/plan.md).

## Stack

- **Infra**: Terraform (`terraform/azure`), state remoto no HCP Terraform.
- **Runtime**: Docker Compose por serviço (`compose/<serviço>/`), orquestrado por `compose/docker-compose.yml` via `include`.
- **LLM**: NVIDIA NIM (`moonshotai/kimi-k3`), free tier.
- **Canal**: Slack, Socket Mode.

## Estrutura

```
terraform/azure/      # VM, rede, firewall
terraform/scripts/    # cloud-init (Docker)
compose/<serviço>/    # docker-compose.yml + config declarativo por serviço
docs/                 # plano do projeto e specs de design
```

## Como rodar

```bash
cd terraform/azure
terraform login && terraform init && terraform plan   # infra

cd compose
docker compose up -d   # runtime, na VM
```

Segredos ficam em `compose/<serviço>/.env` (fora do git). Um pre-commit com [gitleaks](.githooks/pre-commit) bloqueia commit de credencial — ativa uma vez com `git config core.hooksPath .githooks`.
