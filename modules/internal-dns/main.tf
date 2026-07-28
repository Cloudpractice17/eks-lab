# WHY a module: Phase 1 hardcoded one app's load balancer directly in
# main.tf. That doesn't scale — adding Jenkins or Argo CD to your internal
# DNS would mean copy-pasting the same data source + record block again.
# A module takes a map of records and loops over it with for_each, so
# adding a new service is a one-line change to a variable, not new code.

resource "aws_route53_zone" "internal" {
  name = var.zone_name

  vpc {
    vpc_id     = var.vpc_id
    vpc_region = var.aws_region
  }

  tags = var.tags
}

data "aws_lb" "apps" {
  for_each = var.records
  name     = each.value
}

resource "aws_route53_record" "apps" {
  for_each = var.records

  zone_id = aws_route53_zone.internal.zone_id
  name    = "${each.key}.${var.zone_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.apps[each.key].dns_name
    zone_id                = data.aws_lb.apps[each.key].zone_id
    evaluate_target_health = true
  }
}
