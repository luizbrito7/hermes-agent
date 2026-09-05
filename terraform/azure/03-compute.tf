variable "admin_username" {
  description = "Usuário admin da VM"
  type        = string
  default     = "hermes"
}

variable "ssh_public_key_path" {
  description = "Caminho local da chave pública SSH"
  type        = string
  default     = "~/.ssh/hermes_vm.pub"
}

resource "azurerm_public_ip" "main" {
  name                = "pip-${local.project}-${local.env}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "main" {
  name                = "nic-${local.project}-${local.env}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "azurerm_linux_virtual_machine" "main" {
  name                            = "vm-${local.project}-${local.env}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = "Standard_B2s"
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.main.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/../scripts/user-data.sh.tftpl", {
    admin_username = var.admin_username
  }))
}

output "vm_public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "ssh_command" {
  value = "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}
