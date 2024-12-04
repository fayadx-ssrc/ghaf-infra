# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

resource "azurerm_resource_group" "default" {
  name     = var.environment_name
  location = var.location
}

output "resource_group_name" {
  value = azurerm_resource_group.default.name
}