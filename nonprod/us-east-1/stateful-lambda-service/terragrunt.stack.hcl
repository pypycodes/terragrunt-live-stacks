locals {
  name = "${get_env("EX_APP_PREFIX", "")}stateful-lambda-service-dev"
}

unit "lambda_service" {
  // You'll typically want to pin this to a particular version of your catalog repo.
  // e.g.
  // source = "github.com/acme/terragrunt-infrastructure-catalog//units/lambda-stateful-service?ref=v0.1.0"
  //
  // If you are using a private catalog, you may want to use an SSH source URL instead:
  // source = "git::git@github.com:acme/terragrunt-infrastructure-catalog.git//units/lambda-stateful-service"
  source = "github.com/pypycodes/terragrunt-infrastructure-catalog-example//units/js-lambda-stateful-service"

  path = "service"

  values = {
    // This version here is used as the version passed down to the unit
    // to use when fetching the OpenTofu/Terraform module.
    version = "main"

    name = local.name

    // Required inputs
    runtime    = "nodejs22.x"
    source_dir = "./src"
    handler    = "index.handler"
    zip_file   = "handler.zip"

    // Optional inputs
    memory  = 128
    timeout = 3
  }

  // Stacks dependencies wire cross-unit relationships in the stack file via unit.<name>.path
  autoinclude {
    dependency "role" {
      config_path = unit.role.path

      mock_outputs = {
        arn = "arn:aws:iam::123456789012:role/lambda-iam-role-to-dynamodb"
      }
    }

    dependency "dynamodb_table" {
      config_path = unit.db.path

      mock_outputs = {
        name = "dynamodb-table"
      }
    }
  }
}

unit "db" {
  // You'll typically want to pin this to a particular version of your catalog repo.
  // e.g.
  // source = "github.com/acme/terragrunt-infrastructure-catalog//units/dynamodb-table?ref=v0.1.0"
  //
  // If you are using a private catalog, you may want to use an SSH source URL instead:
  // source = "git::git@github.com:acme/terragrunt-infrastructure-catalog.git//units/dynamodb-table"
  source = "github.com/gruntwork-io/terragrunt-infrastructure-catalog-example//units/dynamodb-table"

  path = "db"

  values = {
    // This version here is used as the version passed down to the unit
    // to use when fetching the OpenTofu/Terraform module.
    version = "main"

    name          = "${local.name}-db"
    hash_key      = "Id"
    hash_key_type = "S"
  }
}

unit "role" {
  # source = "github.com/gruntwork-io/terragrunt-infrastructure-catalog-example//units/lambda-iam-role-to-dynamodb"
  source = "github.com/pypycodes/terragrunt-infrastructure-catalog-example//units/lambda-iam-role-to-dynamodb"

  path = "roles/lambda-iam-role-to-dynamodb"

  values = {
    version = "main"

    name = "${local.name}-role"

    policy = jsonencode({
      Version = "2012-10-17"

      Statement = [
        {
          Effect = "Allow"

          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem",
            "dynamodb:Query",
            "dynamodb:Scan"
          ]

          Resource = "*"
        }
      ]
    })
  }

  autoinclude {
    dependency "dynamodb_table" {
      config_path = unit.db.path

      mock_outputs = {
        arn = "arn:aws:dynamodb:us-east-1:123456789012:table/example-table"
      }
    }
  }
}