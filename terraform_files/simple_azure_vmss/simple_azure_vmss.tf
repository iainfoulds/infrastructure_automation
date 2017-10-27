variable "resourcename" {
  default = "myTerraformVMSS"
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  subscription_id = "${var.subscription_id}"
  client_id       = "${var.client_id}"
  client_secret   = "${var.client_secret}"
  tenant_id       = "${var.tenant_id}"
}

# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "myterraform" {
    name = "myTerraformVMSS"
    location = "East US"

    tags {
        environment = "Terraform Demo"
    }
}

# Create virtual network
resource "azurerm_virtual_network" "myterraformnetwork" {
    name = "myVnet"
    address_space = ["10.0.0.0/16"]
    location = "East US"
    resource_group_name = "${azurerm_resource_group.myterraform.name}"

    tags {
        environment = "Terraform Demo"
    }
}

# Create subnet
resource "azurerm_subnet" "myterraformsubnet" {
    name = "mySubnet"
    resource_group_name = "${azurerm_resource_group.myterraform.name}"
    virtual_network_name = "${azurerm_virtual_network.myterraformnetwork.name}"
    address_prefix = "10.0.1.0/24"
}

# Create public IP address for load  balancer front-end
resource "azurerm_public_ip" "myterraformpublicip" {
    name                         = "myPublicIP"
    location                     = "East US"
    resource_group_name          = "${azurerm_resource_group.myterraform.name}"
    public_ip_address_allocation = "static"

    tags {
        environment = "Terraform Demo"
    }
}

# Create load balancer
resource "azurerm_lb" "myterraformloadbalancer" {
    name                = "myLoadBalancer"
    location            = "East US"
    resource_group_name = "${azurerm_resource_group.myterraform.name}"

    frontend_ip_configuration {
        name                 = "PublicIPAddress"
        public_ip_address_id = "${azurerm_public_ip.myterraformpublicip.id}"
    }

    tags {
        environment = "Terraform Demo"
    }
}

# Create load balancer back-end address pool
resource "azurerm_lb_backend_address_pool" "myterraformbackendpool" {
    resource_group_name = "${azurerm_resource_group.myterraform.name}"
    loadbalancer_id     = "${azurerm_lb.myterraformloadbalancer.id}"
    name                = "BackEndAddressPool"
}

# Create load balancer NAT pool and rules for remote connectivity to VM instances
resource "azurerm_lb_nat_pool" "myterraformnatpool" {
    count                          = 5
    resource_group_name            = "${azurerm_resource_group.myterraform.name}"
    name                           = "SSH"
    loadbalancer_id                = "${azurerm_lb.myterraformloadbalancer.id}"
    protocol                       = "Tcp"
    frontend_port_start            = 50000
    frontend_port_end              = 50119
    backend_port                   = 22
    frontend_ip_configuration_name = "PublicIPAddress"
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = "${azurerm_resource_group.myterraform.name}"
    }
    
    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "mystorageaccount" {
    name = "diag${random_id.randomId.hex}"
    resource_group_name = "${azurerm_resource_group.myterraform.name}"
    location = "East US"
    account_replication_type = "LRS"
    account_tier = "Standard"

    tags {
        environment = "Terraform Demo"
    }
}


# Create virtual machine scale set
resource "azurerm_virtual_machine_scale_set" "myterraformvmss" {
    name                = "myVMSS"
    location            = "East US"
    resource_group_name = "${azurerm_resource_group.myterraform.name}"
    upgrade_policy_mode = "Manual"

    sku {
        name     = "Standard_DS1_v2"
        tier     = "Standard"
        capacity = 5
    }

    storage_profile_os_disk {
        name              = ""
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
    }

    storage_profile_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }

    os_profile {
        computer_name_prefix = "myvm"
        admin_username = "azureuser"
        admin_password = ""
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path = "/home/azureuser/.ssh/authorized_keys"
            key_data = "${var.ssh_public_key}"
        }
    }

    boot_diagnostics {
        enabled = "true"
        storage_uri = "${azurerm_storage_account.mystorageaccount.primary_blob_endpoint}"
    }

    network_profile {
        name    = "terraformnetworkprofile"
        primary = true

        ip_configuration {
            name                                   = "myIPConfiguration"
            subnet_id                              = "${azurerm_subnet.myterraformsubnet.id}"
            load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.myterraformbackendpool.id}"]
            load_balancer_inbound_nat_rules_ids    = ["${element(azurerm_lb_nat_pool.myterraformnatpool.*.id, count.index)}"]
        }
    }

    tags {
        environment = "Terraform Demo"
    }
}