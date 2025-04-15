variable platforms {
  default = ( split(",", "linux/arm64,linux/amd64") )
}

target "platforms" {
  platforms =  platforms
}

target "common" {
  inherits = [ "platforms" ]
}
