terraform {
  backend "azurerm" {
    resource_group_name  = "snflk_training_rg"
    storage_account_name = "fspsftpsource"
    container_name       = "tfstate"
    key                  = "environments/dev/terraform.tfstate"
    use_azuread_auth     = true
  }
}
