variable "cluster_name" {
  type        = string
  description = "Cluster name. Used in the GitHub repo description, deploy-key title, and as the default Flux watch path (clusters/<cluster_name>)."
}

variable "github_repo" {
  type        = string
  description = "Name of the GitHub repository Flux watches. Created by this module as a private repo."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo: letters, digits, dots, hyphens and underscores only."
  }
}

variable "flux_path" {
  type        = string
  description = "Path inside the Git repo Flux watches. Defaults to clusters/<cluster_name> when null."
  default     = null
}

variable "deploy_key_read_only" {
  type        = bool
  description = "If true, registers the Flux deploy key as read-only. Set false (default) when you want Flux Image Automation to push tags back to the repo."
  default     = false
}

variable "auto_init_repo" {
  type        = bool
  description = "Whether `github_repository.auto_init` is set. Required for Flux to be able to clone the repo on bootstrap (without it the SSH clone fails on an empty repository)."
  default     = true
}
