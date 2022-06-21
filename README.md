# humio-bootstrap

The current implementation runs on AWS only and downloads files from a bucket. Needs arguments and configurability.

## Terraform
If you wish to use terraform to provision the infrastructure needed for humio-bootstrap do the following.

```
cd terraform
tar -C ../ansible -czf ansible.tar.gz .
```

Set any AWS specific environmental variables you need to so that terraform can authenticate with AWS.

Then run
```
terraform init
terraform apply
```

Optionally override any variables by passing `-var="<variable_name>=<variable_value>"` to terraform apply
