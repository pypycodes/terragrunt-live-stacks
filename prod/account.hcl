# Set account-wide variables. These are automatically pulled in to configure the remote state bucket in the root
# root.hcl configuration.
locals {
  account_name   = "prod"
  aws_account_id = get_env("EX_PROD_ACCOUNT_ID")
  aws_profile    = get_env("EX_PROD_PROFILE")
}
