################################################################################
# PostgreSQL on RDS in the isolated database subnets.
#
# The master password is generated and rotated by RDS itself and stored in
# Secrets Manager (manage_master_user_password), so it never appears in
# Terraform state or in Git. Pods get it via External Secrets Operator.
################################################################################

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.identifier}-"
  description = "Database subnets for ${var.identifier}"
  subnet_ids  = var.subnet_ids
  tags        = var.tags
}

resource "aws_security_group" "this" {
  name_prefix = "${var.identifier}-db-"
  description = "PostgreSQL access for ${var.identifier}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.identifier}-db" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.identifier}-"
  family      = "postgres${var.engine_major_version}"
  description = "Parameters for ${var.identifier}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # log queries slower than 500ms
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Pre-create the log groups RDS exports to, so they get a retention period
# (RDS would otherwise create them with "never expire").
resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(["postgresql", "upgrade"])

  name              = "/aws/rds/instance/${var.identifier}/${each.value}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine                     = "postgres"
  engine_version             = var.engine_major_version
  auto_minor_version_upgrade = true
  instance_class             = var.instance_class
  parameter_group_name       = aws_db_parameter_group.this.name

  db_name                             = var.database_name
  username                            = var.master_username
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period   = var.backup_retention_days
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = var.performance_insights_enabled
  apply_immediately               = var.apply_immediately

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.rds]
}
