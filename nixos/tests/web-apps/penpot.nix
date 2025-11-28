import ../make-test-python.nix ({ pkgs, lib, ... }:
{
  name = "penpot";

  nodes.machine = { ... }: {
    services.penpot = {
      enable = true;
      secretKey = "test-secret-123";
      publicUri = "http://penpot.local:9001";
      nginx.enable = true;
    };
    networking.firewall.allowedTCPPorts = [ 9001 ];
    networking.extraHosts = "127.0.0.1 penpot.local";
  };

  nodes.backendOnly = { ... }: {
    services.penpot = {
      enable = true;
      secretKey = "test-secret-123";
      publicUri = "http://backend.local:6060";
      nginx.enable = false;
    };
    networking.firewall.allowedTCPPorts = [ 6060 ];
    networking.extraHosts = "127.0.0.1 backend.local";
  };

  testScript = ''
    # Backend-only instance (nginx disabled)
    backendOnly.start()
    backendOnly.wait_for_unit("penpot-backend.service")
    backendOnly.wait_for_unit("penpot-exporter.service")
    backendOnly.wait_for_open_port(6060)
    backendOnly.wait_until_succeeds("curl -sSf http://127.0.0.1:6060/readyz")
    backendOnly.succeed("test -d /var/lib/penpot/assets")

    # Full instance with nginx proxying frontend + API
    machine.start()
    machine.wait_for_unit("penpot-backend.service")
    machine.wait_for_unit("penpot-exporter.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(6060)
    machine.wait_until_succeeds("curl -sSf http://127.0.0.1:6060/readyz")
    machine.wait_for_open_port(9001)
    machine.succeed("curl -sSf --resolve penpot.local:9001:127.0.0.1 http://penpot.local:9001/readyz")
    machine.succeed("curl -sSf --resolve penpot.local:9001:127.0.0.1 http://penpot.local:9001/ | grep -i penpot")
    machine.succeed("curl -sSf --resolve penpot.local:9001:127.0.0.1 http://penpot.local:9001/js/config.js | grep penpotFlags")
    machine.succeed("test -d /var/lib/penpot/assets")
  '';
})
