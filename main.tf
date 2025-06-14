provider "aws" {
  region = "us-east-1"
}

# Create a VPC named ‘wordpress-vpc’ (add name tag).

module "vpc" {
  source     = "./vpc"
  cidr_block = "192.168.0.0/16"
  name       = "wordpress-vpc"
}

# Create an Internet Gateway named ‘wordpress_igw’ (add name tag).

module "ig" {
  source = "./ig"
  vpc_id = module.vpc.id
  name   = "wordpress_igw"
}

# Create a route table named ‘wordpess-rt’ and add Internet Gateway route to it (add name tag).

module "public_rt" {
  source     = "./rt"
  vpc_id     = module.vpc.id
  cidr_block = "0.0.0.0/0"
  gateway_id = module.ig.id
  name       = "wordpess-rt"
}

# Create 3 public and 3 private subnets in the us-east region (add name tag). Associate them with the ‘wordpess-rt’ route table. What subnets should be associated with the ‘wordpess-rt’ route table? What about other subnets? Use AWS documentation.

module "public_subnets" {
  source                  = "./subnet"
  vpc_id                  = module.vpc.id
  map_public_ip_on_launch = true

  for_each = local.public_subnets

  name              = each.key
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
}

module "private_subnets" {
  source                  = "./subnet"
  vpc_id                  = module.vpc.id
  map_public_ip_on_launch = false

  for_each = local.private_subnets

  name              = each.key
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
}

resource "aws_route_table_association" "public" {
  for_each = module.public_subnets

  subnet_id      = each.value.id
  route_table_id = module.public_rt.id
}

resource "aws_route_table_association" "private" {
  for_each = module.private_subnets

  subnet_id      = each.value.id
  route_table_id = module.private_rt.id
}


# Create a security group named ‘wordpress-sg’ and open HTTP, HTTPS, SSH ports to the Internet (add name tag). Define port numbers in a variable named ‘ingress_ports’.

module "wordpress-sg" {
  source = "./sg"
  name = "wordpress-sg"
  description = "Allow ssh, http and https"
  vpc_id = module.vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "ingress" {
  for_each = local.ingress_ports
  
  description = "allow inbound ${each.key} access"
  security_group_id = module.wordpress-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value
  ip_protocol       = "tcp"
  to_port           = each.value

  tags = {
    Name = "allow ${each.key} access"
  }
}

resource "aws_vpc_security_group_egress_rule" "egress" {
  security_group_id = module.wordpress-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
  
  tags = {
    Name = "allow all access"
  }
}


// TODO: Create a key pair named ‘ssh-key’ (you can use your public key).

module "nat_gw" {
  source     = "./nat"
  depends_on = [module.ig]
  subnet_id  = module.public_subnets["public_subnet_1"].id
  name       = "nat-gw"
}

module "private_rt" {
  source     = "./rt"
  vpc_id     = module.vpc.id
  cidr_block = "0.0.0.0/0"
  gateway_id = module.nat_gw.id
  name       = "private-rt"
}

output "ec2_public_ip" {
  value = module.webserver.public_ip
}



# Create an EC2 instance named ‘wordpress-ec2’ (add name tag). Use Amazon Linux 2 AMI (can store AMI in a variable), t2.micro, ‘wordpress-sg’ security group, ‘ssh-key’ key pair, public subnet 1.

# You have to install wordpress on 'wordpress-ec2'. Desired result: on wordpress-ec2-public-ip/blog address, you have to see wordpress installation page. You can install wordpress manually or through user_data. 

module "webserver" {
  source = "./ec2"
  ami = "ami-09e6f87a47903347c"
  instance_type = "t2.micro"
  key_name = "linuxkey"
  vpc_security_group_ids = [module.wordpress-sg.id]
  subnet_id = module.public_subnets["public_subnet_1"].id
  user_data = file("${path.module}/scripts/user_data.sh")
  name = "wordpress-ec2"
}

# Create a security group named ‘rds-sg’ and open MySQL port and allow traffic only from ‘wordpress-sg’ security group (add name tag).

module "rds-sg" {
  source = "./sg"
  name = "rds-sg"
  description = "Allow ssh access from wordpress-sg"
  vpc_id = module.vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_" {
  security_group_id = module.rds-sg.id
  referenced_security_group_id         = module.wordpress-sg.id
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306

  tags = {
    Name = "allow access only from wordpress-sg"
  }
}

# Create a MySQL DB instance named ‘mysql’: 20GB, gp2, t2.micro instance class, username=admin, password=adminadmin. Use ‘aws_db_subnet_group’ resource to define private subnets where the DB instance will be created.

resource "aws_db_subnet_group" "mysql_subnet_group" {
  name       = "mysql-subnet-group"
  subnet_ids = [for subnet in module.private_subnets : subnet.id]

  tags = {
    Name = "mysql-subnet-group"
  }
}

module "aws_db_instance" {
  source = "./db_ec2"
  
  engine = "mysql"
  engine_version = "8.0.34"
  
  identifier             = "mysql"
  instance_class         = "db.t3.micro"
  allocated_storage      = "20"
  storage_type           = "gp2"
  username               = "admin"
  password               = "adminadmin"
  db_subnet_group_name   = aws_db_subnet_group.mysql_subnet_group.name
  vpc_security_group_ids = [module.rds-sg.id]
  skip_final_snapshot    = true
  name = "MySQL for WordPress"
}

