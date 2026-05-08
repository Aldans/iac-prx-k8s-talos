// TFLint config — enables the bundled Terraform ruleset on the recommended
// preset (deprecation warnings, naming conventions, unused declarations,
// required attributes for module sources, etc.). See:
// https://github.com/terraform-linters/tflint-ruleset-terraform/blob/main/docs/rules/README.md

config {
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
