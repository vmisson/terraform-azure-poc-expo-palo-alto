variable "subscription_id" {
  type = string
}

variable "region" {
  type    = string
  default = "France Central"
}

variable "address_space" {
  type    = string
  default = "10.100.0.0/23"
}

variable "firewall_name" {
  type    = string
  default = "fw01"
}

variable "size" {
  type    = string
  default = "Standard_D3_v2"
}

variable "username" {
  type    = string
  default = "panadmin"
}

variable "bootstrap_options" {
  type    = string
  default = null
}

variable "ip_count" {
  type    = number
  default = 6
}

variable "spoke_count" {
  type    = number
  default = 3
}
