variable "bucket_name" {
  description = "Globally-unique S3 bucket name. Leave null to auto-generate one based on a random pet name."
  type        = string
  default     = null
}

variable "versioning_enabled" {
  description = "Whether bucket object versioning is enabled."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "If true, terraform destroy deletes all bucket contents before deleting the bucket."
  type        = bool
  default     = false
}

variable "resource_tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}
