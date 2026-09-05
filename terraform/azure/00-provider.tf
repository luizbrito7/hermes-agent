terraform {
  required_version = ">= 1.9.0"

  cloud {
    organization = "org-hermes-agent"
    workspaces {
      name = "ws-hermes-azure"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  project  = "hermes"
  env      = "prd"
  location = "Brazil South"
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.project}-${local.env}"
  location = local.location
}
