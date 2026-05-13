project_name = "kicks-shoes-dev"
aws_region   = "us-west-2"
container_image = "public.ecr.aws/docker/library/nginx:latest"
container_port  = 80
desired_count   = 1
task_cpu        = 256
task_memory     = 512
app_config_secret_name = "kicks-shoes-dev/app-config"
tags = {
  Environment = "dev"
  Project     = "kicks-shoes"
}
