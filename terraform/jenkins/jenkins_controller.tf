# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0

# Build the Jenkins controller image
module "jenkins_controller_image" {
  source = "../../tf-modules/azurerm-nix-vm-image"

  nix_attrpath   = "outputs.nixosConfigurations.jenkins-controller.config.system.build.azureImage"
  nix_entrypoint = "${path.module}/../.."


  name                = "jenkins-controller"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location

  storage_account_name   = azurerm_storage_account.vm_images.name
  storage_container_name = azurerm_storage_container.vm_images.name
}

# Create a machine using this image
module "jenkins_controller_vm" {
  source = "../../tf-modules/azurerm-linux-vm"

  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location

  virtual_machine_name         = "ghaf-jenkins-controller"
  virtual_machine_size         = "Standard_D1_v2"
  virtual_machine_source_image = module.jenkins_controller_image.image_id

  virtual_machine_custom_data = join("\n", ["#cloud-config", yamlencode({
    users = [
      for user in toset(["bmg", "flokli", "hrosten"]) : {
        name                = user
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = local.ssh_keys[user]
      }
    ]
    # mount /dev/disk/by-lun/10 to /var/lib/jenkins
    disk_setup = {
      "/dev/disk/by-lun/10" = {
        layout  = false # don't partition
        timeout = 60    # wait for device to appear
      }
    }
    fs_setup = [
      {
        filesystem = "ext4"
        partition  = "auto"
        device     = "/dev/disk/by-lun/10"
        label      = "jenkins"
      }
    ]
    mounts = [
      ["/dev/disk/by-label/jenkins", "/var/lib/jenkins"]
    ]
  })])

  subnet_id = azurerm_subnet.jenkins.id
}

resource "azurerm_network_interface_security_group_association" "jenkins_controller_vm" {
  network_interface_id      = module.jenkins_controller_vm.virtual_machine_network_interface_id
  network_security_group_id = azurerm_network_security_group.jenkins_controller_vm.id
}

resource "azurerm_network_security_group" "jenkins_controller_vm" {
  name                = "jenkins-controller-vm"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location

  security_rule {
    name                       = "AllowSSHInbound"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [22]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create a data disk
resource "azurerm_managed_disk" "jenkins_controller_jenkins_state" {
  name                 = "jenkins-controller-vm-jenkins-state"
  resource_group_name  = azurerm_resource_group.default.name
  location             = azurerm_resource_group.default.location
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 10
}

# Attach to the VM
resource "azurerm_virtual_machine_data_disk_attachment" "jenkins_controller_vm_jenkins_state" {
  managed_disk_id    = azurerm_managed_disk.jenkins_controller_jenkins_state.id
  virtual_machine_id = module.jenkins_controller_vm.virtual_machine_id
  lun                = "10"
  caching            = "None"
}