# This file defines the variables used in the Terraform configuration.
variable "cluster_name" {
  type    = string
  default = "tl01"
}

variable "prx_node" {
  type    = string
  default = "pv"
}

variable "prx" {
    type = object({
        endpoint     = string
        username     = string
        password     = string
        api_token    = string
      })
    sensitive = true
}

variable "num_control_planes" {
  type    = number
  default = 3
}

variable "num_workers" {
  type    = number
  default = 4
}
