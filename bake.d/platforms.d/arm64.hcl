variable platforms {
  default = ( split(",", "linux/arm64") )
}

variable "nuxeo-image" {
  default = "lts"
}
