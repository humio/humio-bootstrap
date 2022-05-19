terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.14.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.1.1"
    }
  }
}

provider "aws" {
  region = local.region
}
