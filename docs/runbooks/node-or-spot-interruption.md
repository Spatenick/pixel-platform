# Runbook: node NotReady / spot interruption / pods Pending

## Triage

```bash
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase=Pending
kubectl describe node <node>          # Conditions, taints, events
aws eks describe-nodegroup --cluster-name pixelpipe-dev \
  --nodegroup-name "$(aws eks list-nodegroups --cluster-name pixelpipe-dev --query 'nodegroups[0]' --output text)" \
  --query 'nodegroup.health'
```

## What normally happens on a spot interruption

AWS gives a 2-minute warning. The managed node group drains the node: PodDisruptionBudgets allow at most one pod of each service to go at a time, topology spread puts the replacements on other nodes or AZs, and the ASG launches a replacement node. **The API should stay up throughout.** If it doesn't, the PDB or replica count is wrong.

## Causes and fixes

| Looks like | Fix |
|---|---|
| Pods Pending with *Insufficient cpu/memory* | Node group at capacity. Raise `node_desired_size` (PR) or add Karpenter. |
| Node group can't launch spot capacity | Add more instance types to `node_instance_types`, or switch dev to `ON_DEMAND`. |
| Node NotReady, VPC CNI errors | `kubectl -n kube-system logs ds/aws-node`. Often subnet IP exhaustion; check free IPs in the private subnets. |
| Want a shell on a node | `aws ssm start-session --target <instance-id>`. There's no SSH by design. |
