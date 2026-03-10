module "qa" {
  source = "../modules/blog"

  environment = {
    name            = "qa"
    network_prefix  = "10.1"
  }

  asg_settings = {
    min_size          = 1
    max_size          = 3
    desired_capacity  = 2
  }
}