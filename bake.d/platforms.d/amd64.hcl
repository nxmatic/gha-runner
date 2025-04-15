variable platforms {
  default = ( split(",", "linux/amd64") )
}

variable "nuxeo-image" {
  default = "docker-private.packages.nuxeo.com/nuxeo/nuxeo:2023.14.23"
}
