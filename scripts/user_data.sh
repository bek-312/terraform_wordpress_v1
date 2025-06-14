#!/bin/bash
sudo yum update -y
sudo yum install -y httpd

# Start and enable Apache
sudo systemctl start httpd
sudo systemctl enable httpd

# Download and configure WordPress
sudo wget https://wordpress.org/latest.tar.gz -P /tmp
sudo tar -xzf /tmp/latest.tar.gz -C /tmp
sudo mkdir -p /var/www/html/blog
sudo cp -r /tmp/wordpress/* /var/www/html/blog/

# Set correct permissions
sudo chown -R apache:apache /var/www/html/blog
sudo chmod -R 755 /var/www/html/blog