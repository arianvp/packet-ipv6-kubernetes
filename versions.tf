terraform {
  required_version = ">= 0.13"
  required_providers {
    metal = {
      source = "equinix/metal"
      # version = "1.0.0"
    }
    ct = {
      source  = "poseidon/ct"
      version = "~> 0.9.0"
    }
  }
}
