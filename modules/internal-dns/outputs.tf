output "zone_id" {
  description = "Route 53 hosted zone ID — needed by Phase 2 health checks"
  value       = aws_route53_zone.internal.zone_id
}

output "record_fqdns" {
  description = "Map of app name to its full internal DNS name"
  value       = { for k, r in aws_route53_record.apps : k => r.name }
}

output "nameservers" {
  description = "Informational only — private zones don't need external delegation"
  value       = aws_route53_zone.internal.name_servers
}
