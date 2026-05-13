output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "vpc_cidr" {
  value = data.aws_vpc.default.cidr_block
}

output "public_subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "private_subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "db_subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "db_subnet_group_name" {
  value = ""
}

output "nat_public_ips" {
  value = [] 
}
