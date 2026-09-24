terraform {
  backend "s3" {
    bucket  = "gitops-terraformcode007"
    key     = "eks/terraform.tfstate"
    region  = "us-east-1"
  }
}
