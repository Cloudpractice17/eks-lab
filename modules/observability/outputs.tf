output "sns_topic_arn" {
  description = "Subscribe Slack or PagerDuty here for real-time alerts"
  value       = aws_sns_topic.alerts.arn
}
