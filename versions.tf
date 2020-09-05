terraform {
  required_version = ">= 0.13"
  required_providers {
    packet = {
      source  = "packethost/packet"
      version = "3.0.1"
    }
    ct = {
      source  = "poseidon/ct"
      version = "~> 0.6.1"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 1.22.2"
    }
  }
}
