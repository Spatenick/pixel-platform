# Runbook: `terraform destroy` is stuck or fails

Almost always the cause is an AWS resource **created by Kubernetes, not Terraform**, still sitting in the VPC: an ALB from the Ingress, its security groups, or ENIs. `scripts/teardown.sh` prevents this, but a plain `terraform destroy` doesn't.

## Find what's in the way

```bash
VPC=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=pixelpipe-dev --query 'Vpcs[0].VpcId' --output text)
aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC'].[LoadBalancerName,LoadBalancerArn]" --output table
aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=$VPC --query 'NetworkInterfaces[].[NetworkInterfaceId,Description,Status]' --output table
aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC --query 'SecurityGroups[].[GroupId,GroupName]' --output table
```

## Fix

1. Delete leftover ALBs (names start with `k8s-`): `aws elbv2 delete-load-balancer --load-balancer-arn <arn>`
2. Wait a minute for their ENIs to go, then delete leftover `k8s-` security groups: `aws ec2 delete-security-group --group-id <id>`
3. Delete target groups named `k8s-…`: `aws elbv2 delete-target-group --target-group-arn <arn>`
4. Re-run `make down ENV=dev`.

## If state is locked

Another apply is running, or one crashed. Check GitHub Actions first. If nothing is running:

```bash
terraform -chdir=infra/envs/dev force-unlock <LOCK_ID>   # the ID is in the error message
```
