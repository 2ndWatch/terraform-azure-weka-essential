terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  backend "azurerm" {
    resource_group_name  = "az-eastus-weka-tf-state-rg"
    storage_account_name = "azeastuswekatfstate01"
    container_name       = "azeastuswekatfstatecon01"
    key                  = "weka.tfstate"
    use_azuread_auth     = true
    subscription_id      = "13b706d3-f7a2-4e89-91d3-921288c68091"
    tenant_id            = "8242a0a9-c415-4206-be39-06637ad2817a"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.9.0, < 3.52.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "13b706d3-f7a2-4e89-91d3-921288c68091"

  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "weka-example"
  location = "eastus"
}

module "weka_deployment" {
  source            = "../.."
  prefix            = "essential"
  rg_name           = "weka-example"
  cluster_name      = "test"
  instance_type     = "Standard_L8s_v3"
  cluster_size      = 6
  get_weka_io_token = "..."
}

output "weka_deployment_output" {
  value = module.weka_deployment
}
