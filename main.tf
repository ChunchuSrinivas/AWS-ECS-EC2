#Defining Local User Data
     locals {
       user_data = <<-EOF
             #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl start docker
              systemctl enable docker
              yum install -y amazon-efs-utils
              systemctl enable --now --no-block amazon-ecs-volume-plugin
              mkdir -p /etc/ecs
              touch /etc/ecs/ecs.config
              echo "ECS_CLUSTER=ramp-dev" > /etc/ecs/ecs.config
              echo "ECS_LOGLEVEL=debug" >> /etc/ecs/ecs.config
              echo "ECS_AVAILABLE_LOGGING_DRIVERS=[\"json-file\",\"awslogs\",\"awsfirelens\"]" >> /etc/ecs/ecs.config
              echo "ECS_ENABLE_TASK_IAM_ROLE=true" >> /etc/ecs/ecs.config
              echo "ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true" >> /etc/ecs/ecs.config
              yum install -y ecs-init
              systemctl enable --now --no-block ecs.service
              systemctl start amazon-ecs-volume-plugin
              sudo mkdir /home/ubuntu/node_exporter
              cd node_exporter/
              sudo wget https://github.com/prometheus/node_exporter/releases/download/v1.2.2/node_exporter-1.2.2.linux-amd64.tar.gz
              sudo tar -xf node_exporter-1.2.2.linux-amd64.tar.gz
              cd node_exporter-1.2.2.linux-amd64
              ./node_exporter &
              EOF
    }

#Defining EC2 Machine
resource "aws_launch_template" "ecs-short-url-service-ec2" {
   name                   = var.ecs_ec2_launch_template #replace with aws launch template name
   image_id               = var.ami_id
   instance_type          = var.instance_type
   key_name               = var.key_name    
   vpc_security_group_ids = var.security_grps
   
     iam_instance_profile {
                   name = "ecsInstanceRole"
     }
  
  #Configure spot instances
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "0.05"  
    }
  }
  
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 10
      volume_type = "gp3"
    }
  } 

user_data = base64encode(local.user_data)

     tag_specifications {
        resource_type = "instance"
   
          tags = {
               Name = var.ecs_ec2_name_tag
          }
 
     }
}

#Defining AutoScaling, use only once to create auto scaling group
resource "aws_autoscaling_group" "ecs-ec2-asg" { 
vpc_zone_identifier = var.sub_nets 

   name = "ramp-dev-ecs-ec2-gateway" #replace with auto scaling group
   desired_capacity    = 1
   max_size            = 3
   min_size            = 0

 launch_template {
   id      = aws_launch_template.ecs-short-url-service-ec2.id
   version = "$Latest"
 }
   tag {
      key                 = "AmazonECSManaged"
      value               = "true"
      propagate_at_launch = true
   }
   lifecycle {
      create_before_destroy = true
    }
}

resource "aws_alb_listener_rule" "ecs-ec2-listener-rule" {
  listener_arn = var.listener_arn #replace with listener rule 
    
  action {
     type             = "forward"
     target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
  
  condition {
         host_header {
              values = var.host_header #replace with based on service
         }
  }  
  
}

#Defining Target Group
resource "aws_lb_target_group" "ecs_tg" {
 name        = var.tg_grp #replace with service target group name
 port        = 80
 protocol    = "HTTP"
 target_type = "ip"
 vpc_id      = var.vpc_id 

 health_check {
   path = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200-299"
 }
   tags = {
      Name = var.ecs_service_name #replace with your own tags
  }

}

#Defining ECS capacity provider, use only once to create capacity provider
resource "aws_ecs_capacity_provider" "ramp-dev-cp" {
  name = var.capacity_provider #replace with capacity provider name
  
    auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs-ec2-asg.arn
    managed_termination_protection = "ENABLED"
    }

}


#ECS Service Creation
resource "aws_ecs_service" "ecs-ec2-service" {
  name            = var.ecs_service_name #replace with service name
  cluster         = var.ecs_cluster #replace with cluster name
  task_definition = aws_ecs_task_definition.ecs_task_def.arn
  desired_count   = 1
  
  network_configuration{
                subnets                 = var.sub_nets
                security_groups         = var.sg_grps
                assign_public_ip        = "false"
        }  
 
   capacity_provider_strategy {
   capacity_provider = var.dev_cp
   weight            = 100
   base              = 1
   } 
   load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = var.ecs_service_name #replace with container name
    container_port   = 80 #replace with container port
    }
  depends_on = [
    aws_alb_listener_rule.ecs-ec2-listener-rule
  ]


 deployment_controller {
    type = "ECS"
  }  
 
    tags = {
      Name = var.ecs_service_name #replace with service name
    }
}

#ECS Task Definition
resource "aws_ecs_task_definition" "ecs_task_def" {
   family                   = var.ecs_service_name  
   container_definitions    = file(var.ecs_service_name_json) #replace json file with related service  
   network_mode = "awsvpc"
   }

#Endoffile
