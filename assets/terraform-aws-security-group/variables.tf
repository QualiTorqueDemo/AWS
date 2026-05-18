variable "name" {
  description = "Security group name."
  type        = string
}

variable "description" {
  description = "Security group description."
  type        = string
  default     = "Managed by Torque"
}

variable "vpc_id" {
  description = "VPC in which to create the security group."
  type        = string
}

variable "ingress_rules" {
  description = "List of ingress rule objects. Each: {from_port, to_port, ip_protocol, cidr_ipv4, description (optional)}."
  type = list(object({
    from_port   = number
    to_port     = number
    ip_protocol = string
    cidr_ipv4   = string
    description = optional(string)
  }))
  default = []
}

variable "egress_rules" {
  description = "List of egress rule objects. Same shape as ingress_rules."
  type = list(object({
    from_port   = number
    to_port     = number
    ip_protocol = string
    cidr_ipv4   = string
    description = optional(string)
  }))
  default = [
    {
      from_port   = -1
      to_port     = -1
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "allow-all-out"
    }
  ]
}

variable "tags" {
  description = "Tags applied to the security group and its rules."
  type        = map(string)
  default     = {}
}
