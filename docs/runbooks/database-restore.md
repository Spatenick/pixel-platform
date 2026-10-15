# Runbook: restore the database (point-in-time)

Use this when data was corrupted or deleted, or to rehearse recovery during a game day. **RPO:** about 5 minutes (RDS continuous backups). **RTO:** around 20–30 minutes, so measure it.

1. **Pick the restore time** (just before the incident, in UTC).
2. **Restore to a new instance** (RDS never restores in place):
   ```bash
   ENV=dev
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier pixelpipe-$ENV \
     --target-db-instance-identifier pixelpipe-$ENV-restore \
     --restore-time 2026-01-01T12:00:00Z \
     --db-subnet-group-name "$(aws rds describe-db-instances --db-instance-identifier pixelpipe-$ENV --query 'DBInstances[0].DBSubnetGroup.DBSubnetGroupName' --output text)" \
     --vpc-security-group-ids "$(aws rds describe-db-instances --db-instance-identifier pixelpipe-$ENV --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)" \
     --no-publicly-accessible
   aws rds wait db-instance-available --db-instance-identifier pixelpipe-$ENV-restore
   ```
3. **Verify the data** from inside the cluster:
   ```bash
   kubectl -n pixelpipe run psql --rm -it --image=postgres:17-alpine -- \
     psql "host=<restore-endpoint> user=pixelpipe dbname=pixelpipe sslmode=require" -c 'select count(*), max(created_at) from images;'
   ```
   (The password comes from the original instance's secret in Secrets Manager.)
4. **Cut over.** Either copy the missing rows back into the original instance, or, for a full restore, swap the instance identifiers (rename original → `-old`, restore → original) so Terraform keeps managing the same name, then restart the pods: `kubectl -n pixelpipe rollout restart deploy`.
5. **Clean up** the extra instance, and write down the actual RTO in the postmortem.

> In prod, `deletion_protection` is on and `terraform destroy` keeps a final snapshot.
