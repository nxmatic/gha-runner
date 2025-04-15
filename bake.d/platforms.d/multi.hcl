variable platforms {
  default = ( split(",", "linux/arm64,linux/amd64") )
}

variable "nuxeo-image" {
  default = "lts"
}
