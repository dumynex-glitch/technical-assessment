terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
  }
}

# NOTE: no backend block on purpose.
# State backend (S3 + DynamoDB lock) is environment-specific and created by the
# platform team. Adding it here would require live credentials to even run
# `terraform init -backend=false` in CI validation. Configure the backend in an
# environment-specific override file or via `terraform init -backend-config=...`.
