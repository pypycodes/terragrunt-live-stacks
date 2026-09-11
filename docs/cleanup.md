
```bash
rm -rf .terragrunt-stack
find . -type d -name ".terragrunt-cache" -exec rm -rf {} +
terragrunt stack generate
terragrunt run --all --non-interactive --bootstrap plan
terragrunt run --all --non-interactive --bootstrap apply
terragrunt run --all --non-interactive apply
terragrunt run --all --non-interactive destroy
```