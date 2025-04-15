variable DOCKER_UPSTREAM {
  default = "host.nerd.internal:5000"
}

variable "GITHUB_REPOSITORY" {
  default = "nuxeo/nos"
}

target common {
  args = {
    "org.opencontainers.image.url" = "http://${DOCKER_UPSTREAM}"
    "org.opencontainers.image.source" = "https://github.com/${GITHUB_REPOSITORY}"
  }
  driver = "docker-container"
  cache-from = [ "type=gha" ]
  cache-to = [ "type=gha,mode=max" ]
  output = [ "type=registry" ]
}
