# WHY observability is infrastructure, not an afterthought:
# In production you don't log into the cluster to find out something
# broke — you get alerted before users notice. This module wires up:
# - SNS topic for all alarms (email / Slack / PagerDuty can subscribe)
# - CloudWatch alarms for EKS node health and Jenkins instance health
# - Log groups with retention so logs don't pile up forever
# - The Kubernetes namespace where Prometheus/Grafana will live
#   (the actual Helm install is in the app pipeline — this just
#   ensures the namespace and its IRSA role exist before it runs)

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
  # WHY count not for_each: there's at most one email subscription.
  # After apply, AWS sends a confirmation email — you must click it
  # or the subscription stays in PendingConfirmation and alarms won't
  # deliver.
}

# --- EKS node health alarm ---
# WHY this specific metric: node_not_ready means pods on that node
# will not be scheduled. If count > 0 for more than 5 minutes,
# something is genuinely wrong with your cluster.
resource "aws_cloudwatch_metric_alarm" "node_not_ready" {
  alarm_name          = "${var.name}-${var.environment}-node-not-ready"
  alarm_description   = "One or more EKS nodes have been NotReady for 5+ minutes"
  namespace           = "ContainerInsights"
  metric_name         = "node_status_condition_not_ready"
  dimensions          = { ClusterName = var.eks_cluster_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# --- Jenkins instance health alarm ---
# WHY StatusCheckFailed: this catches both hardware failures (AWS
# infrastructure under the instance) and OS-level failures (the
# instance itself stopped responding). Either means Jenkins is down.
resource "aws_cloudwatch_metric_alarm" "jenkins_health" {
  alarm_name          = "${var.name}-${var.environment}-jenkins-health"
  alarm_description   = "Jenkins EC2 instance failed status check"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = var.jenkins_instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# --- Pod crash loop alarm ---
# WHY: CrashLoopBackOff is the most common failure mode for a newly
# deployed app. This fires within 5 minutes of a bad deployment,
# giving you time to roll back before users notice.
resource "aws_cloudwatch_metric_alarm" "pod_crash_loop" {
  alarm_name          = "${var.name}-${var.environment}-pod-crash-loop"
  alarm_description   = "One or more pods are in CrashLoopBackOff"
  namespace           = "ContainerInsights"
  metric_name         = "pod_number_of_container_restarts"
  dimensions          = { ClusterName = var.eks_cluster_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# --- Log groups with retention ---
# WHY 30 days, not forever: CloudWatch Logs charges per GB stored.
# 30 days is enough to debug an incident and satisfy most audit
# requirements without an unbounded bill.
resource "aws_cloudwatch_log_group" "jenkins" {
  name              = "/eks-lab/${var.environment}/jenkins"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/eks-lab/${var.environment}/app"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.eks_cluster_name}/cluster"
  retention_in_days = 30
}
