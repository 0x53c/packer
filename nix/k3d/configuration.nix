# nix/k3d/configuration.nix
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./k3d-setup.nix
  ];

  # Base configuration from nixos-base
  networking.hostName = "helios-k3d";
  networking.networkmanager.enable = true;

  # Set your time zone
  time.timeZone = "America/Chicago";

  # User account
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here if needed
    ];
  };

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Enable Docker
  virtualisation.docker.enable = true;

  # Enable K3d dependencies
  boot.kernelModules = [ "br_netfilter" ];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
  };

  # Expanded packages for K3d
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    jq
    htop
    docker-compose
    kubectl
    k3d
    kubernetes-helm
    k9s
  ];

  # Enable OpenSSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";

  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "23.11";
}
