{ config, lib, pkgs, ... }:

let
  cfg = config.services.penpot;
  packages = cfg.packages;
  backend = packages.backend;
  frontend = packages.frontend;
  exporter = packages.exporter;
  assetsDir = cfg.assetsDir;
  tmpDir = cfg.tmpDir;
  domain = cfg.domain;
  redisPort = cfg.redis.port;
  db = cfg.database;
  nginxListen = cfg.nginx.listen;
  penpotFlags = lib.concatStringsSep " " cfg.flags;

  backendRuntimePkgs = with pkgs; [
    imagemagickBig
    fontconfig
    freetype
    lcms2
    libjpeg
    libpng
    libtiff
    libwebp
    libzip
    librsvg
    libheif
    woff2
  ];

  exporterRuntimePkgs = with pkgs; [
    packages.nodejs
    packages.jdk
    playwright-driver
    fontconfig
    freetype
    cairo
    pango
    harfbuzz
    libdrm
    mesa
    wayland
    nss
    nspr
    glib
    dbus
    libxkbcommon
    libuuid
    cups
    alsa-lib
    expat
    xorg.libX11
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXScrnSaver
    xorg.libXtst
  ];

in
{
  options.services.penpot = {
    enable = lib.mkEnableOption "Penpot collaborative design platform";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "penpot.local";
      description = "Domain used by nginx for Penpot.";
    };

    packages = lib.mkOption {
      type = lib.types.submodule {
        options = {
          backend = lib.mkOption { type = lib.types.package; default = pkgs.penpotPackages.penpot-backend; description = "Penpot backend package."; };
          frontend = lib.mkOption { type = lib.types.package; default = pkgs.penpotPackages.penpot-frontend; description = "Penpot frontend package."; };
          exporter = lib.mkOption { type = lib.types.package; default = pkgs.penpotPackages.penpot-exporter; description = "Penpot exporter package."; };
          nodejs = lib.mkOption { type = lib.types.package; default = pkgs.nodejs_22; description = "Node.js runtime for exporter."; };
          jdk = lib.mkOption { type = lib.types.package; default = pkgs.jdk21_headless; description = "JDK runtime for backend."; };
        };
      };
      default = { };
      description = "Packages used for Penpot components.";
    };

    secretKey = lib.mkOption {
      type = lib.types.str;
      default = "change-me";
      description = "Secret key for sessions; set to a strong random string in production.";
    };

    publicUri = lib.mkOption {
      type = lib.types.str;
      default = "http://${domain}:${builtins.toString nginxListen}";
      defaultText = lib.literalExpression ''"http://${domain}:9001"'';
      description = "Public URI for Penpot.";
    };

    flags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "disable-email-verification" "enable-smtp" "disable-secure-session-cookies" ];
      description = "Feature flags passed through PENPOT_FLAGS.";
    };

    assetsDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/penpot/assets";
      description = "Directory for stored assets.";
    };

    tmpDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/penpot/tmp";
      description = "Temporary directory for exporter.";
    };

    smtp = lib.mkOption {
      type = lib.types.submodule {
        options = {
          host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
          port = lib.mkOption { type = lib.types.int; default = 1025; };
          username = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          password = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          tls = lib.mkOption { type = lib.types.bool; default = false; };
          ssl = lib.mkOption { type = lib.types.bool; default = false; };
          fromAddress = lib.mkOption { type = lib.types.str; default = "no-reply@example.com"; };
          replyTo = lib.mkOption { type = lib.types.str; default = "no-reply@example.com"; };
        };
      };
      default = { };
      description = "SMTP settings for Penpot notifications.";
    };

    database = lib.mkOption {
      type = lib.types.submodule {
        options = {
          createLocally = lib.mkOption { type = lib.types.bool; default = true; description = "Create and manage PostgreSQL locally."; };
          package = lib.mkPackageOption pkgs "PostgreSQL" { default = [ "postgresql_15" ]; };
          name = lib.mkOption { type = lib.types.str; default = "penpot"; };
          user = lib.mkOption { type = lib.types.str; default = "penpot"; };
          password = lib.mkOption { type = lib.types.str; default = "penpot"; };
          host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
          port = lib.mkOption { type = lib.types.int; default = 5432; };
        };
      };
      default = { };
      description = "Database configuration.";
    };

    redis = lib.mkOption {
      type = lib.types.submodule {
        options = {
          createLocally = lib.mkOption { type = lib.types.bool; default = true; description = "Enable local Redis/Valkey server for Penpot."; };
          package = lib.mkOption {
            type = lib.types.package;
            default = if pkgs ? valkey then pkgs.valkey else pkgs.redis;
            defaultText = lib.literalMD "`pkgs.valkey` or `pkgs.redis`";
          };
          host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
          port = lib.mkOption { type = lib.types.int; default = 6379; };
          db = lib.mkOption { type = lib.types.int; default = 0; };
        };
      };
      default = { };
      description = "Redis/Valkey configuration.";
    };

    nginx = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption { type = lib.types.bool; default = true; description = "Serve frontend via nginx."; };
          listen = lib.mkOption { type = lib.types.int; default = 9001; description = "Port nginx listens on."; };
        };
      };
      default = { };
    };

    telemetry = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to send anonymous telemetry to the Penpot developers.";
          };
          referer = lib.mkOption {
            type = lib.types.str;
            default = "nixos-module";
            description = "Value reported in PENPOT_TELEMETRY_REFERER.";
          };
        };
      };
      default = { };
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for Penpot services.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!cfg.nginx.enable) ''
      services.penpot.nginx.enable is false: make sure to serve ${frontend}/share/penpot/frontend
      through your own web server or CDN.
    '';

    assertions = [{
      assertion = cfg.secretKey != "change-me";
      message = "services.penpot.secretKey should be set to a strong value.";
    }];

    users.users.penpot = {
      isSystemUser = true;
      group = "penpot";
      home = "/var/lib/penpot";
      createHome = true;
    };
    users.groups.penpot = { };
    users.users.nginx = lib.mkIf cfg.nginx.enable {
      # Allow nginx to read assets served from /var/lib/penpot/assets.
      extraGroups = [ "penpot" ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/penpot 0750 penpot penpot -"
      "d ${assetsDir} 0750 penpot penpot -"
      "d ${tmpDir} 0750 penpot penpot -"
    ];

    fonts.fontconfig.enable = true;

    services.postgresql = lib.mkIf db.createLocally {
      enable = true;
      package = db.package;
      enableTCPIP = true;
      ensureDatabases = [ db.name ];
      ensureUsers = [{ name = db.user; ensureDBOwnership = true; }];
      initialScript = pkgs.writeText "penpot-init.sql" ''
        ALTER ROLE ${db.user} WITH LOGIN PASSWORD '${db.password}';
        ALTER DATABASE ${db.name} OWNER TO ${db.user};
      '';
      authentication = lib.mkForce ''
        local all all trust
        host all all 127.0.0.1/32 trust
        host all all ::1/128 trust
      '';
    };

    services.redis = lib.mkIf cfg.redis.createLocally {
      package = cfg.redis.package;
      servers.penpot = {
        enable = true;
        port = redisPort;
        settings = {
          maxmemory = "128mb";
          "maxmemory-policy" = "volatile-lfu";
        };
      };
    };

    systemd.services.penpot-backend = {
      description = "Penpot backend";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ]
        ++ lib.optional db.createLocally "postgresql.service"
        ++ lib.optional cfg.redis.createLocally "redis-penpot.service";
      requires = lib.optional db.createLocally "postgresql.service"
        ++ lib.optional cfg.redis.createLocally "redis-penpot.service";
      path = backendRuntimePkgs;
      serviceConfig = {
        User = "penpot";
        Group = "penpot";
        WorkingDirectory = "${backend}/share/penpot/backend";
        ExecStart = "${backend}/bin/penpot-backend";
        Restart = "always";
        Environment = [
          "PENPOT_FLAGS=${penpotFlags}"
          "PENPOT_PUBLIC_URI=${cfg.publicUri}"
          "PENPOT_SECRET_KEY=${cfg.secretKey}"
          "PENPOT_HTTP_SERVER_MAX_BODY_SIZE=31457280"
          "PENPOT_HTTP_SERVER_MAX_MULTIPART_BODY_SIZE=367001600"
          "PENPOT_DATABASE_URI=postgresql://${db.host}:${builtins.toString db.port}/${db.name}"
          "PENPOT_DATABASE_USERNAME=${db.user}"
          "PENPOT_DATABASE_PASSWORD=${db.password}"
          "PENPOT_REDIS_URI=redis://${cfg.redis.host}:${builtins.toString redisPort}/${builtins.toString cfg.redis.db}"
          "PENPOT_ASSETS_STORAGE_BACKEND=assets-fs"
          "PENPOT_STORAGE_ASSETS_FS_DIRECTORY=${assetsDir}"
          "PENPOT_TELEMETRY_ENABLED=${lib.boolToString cfg.telemetry.enable}"
          "PENPOT_TELEMETRY_REFERER=${cfg.telemetry.referer}"
          "PENPOT_SMTP_DEFAULT_FROM=${cfg.smtp.fromAddress}"
          "PENPOT_SMTP_DEFAULT_REPLY_TO=${cfg.smtp.replyTo}"
          "PENPOT_SMTP_HOST=${cfg.smtp.host}"
          "PENPOT_SMTP_PORT=${builtins.toString cfg.smtp.port}"
          "PENPOT_SMTP_TLS=${lib.boolToString cfg.smtp.tls}"
          "PENPOT_SMTP_SSL=${lib.boolToString cfg.smtp.ssl}"
          "JAVA_TOOL_OPTIONS=-XX:+IgnoreUnrecognizedVMOptions"
        ]
        ++ lib.optional (cfg.smtp.username != null) "PENPOT_SMTP_USERNAME=${cfg.smtp.username}"
        ++ lib.optional (cfg.smtp.password != null) "PENPOT_SMTP_PASSWORD=${cfg.smtp.password}"
        ++ lib.mapAttrsToList (n: v: "${n}=${v}") cfg.extraEnv;
      };
    };

    systemd.services.penpot-exporter = {
      description = "Penpot exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ]
        ++ lib.optional cfg.redis.createLocally "redis-penpot.service";
      path = exporterRuntimePkgs;
      serviceConfig = {
        User = "penpot";
        Group = "penpot";
        WorkingDirectory = "${exporter}/share/penpot/exporter";
        ExecStart = "${exporter}/bin/penpot-exporter";
        Restart = "always";
        Environment = [
          "PENPOT_PUBLIC_URI=${cfg.publicUri}"
          "PENPOT_REDIS_URI=redis://${cfg.redis.host}:${builtins.toString redisPort}/${builtins.toString cfg.redis.db}"
          "PENPOT_SECRET_KEY=${cfg.secretKey}"
          "PENPOT_TEMPDIR=${tmpDir}"
        ] ++ lib.mapAttrsToList (n: v: "${n}=${v}") cfg.extraEnv;
      };
    };

    services.nginx = lib.mkIf cfg.nginx.enable {
      enable = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      virtualHosts.${domain} = {
        listen = [{ addr = "0.0.0.0"; port = nginxListen; }];
        root = "${frontend}/share/penpot/frontend";
        extraConfig = ''
          etag off;
          charset utf-8;

          location @handle_redirect {
            set $redirect_uri "$upstream_http_location";
            proxy_pass $redirect_uri;
            proxy_set_header Host "$upstream_http_x_host";
            proxy_hide_header etag;
            proxy_hide_header x-amz-id-2;
            proxy_hide_header x-amz-request-id;
            proxy_hide_header x-amz-meta-server-side-encryption;
            proxy_hide_header x-amz-server-side-encryption;
            add_header x-internal-redirect "$redirect_uri";
          }

          location /assets {
            proxy_pass http://127.0.0.1:6060/assets;
            recursive_error_pages on;
            proxy_intercept_errors on;
            error_page 301 302 307 = @handle_redirect;
          }

          location /internal/assets/ {
            internal;
            alias ${assetsDir}/;
          }

          location /api/export {
            proxy_pass http://127.0.0.1:6061;
          }

          location /api {
            proxy_pass http://127.0.0.1:6060/api;
            proxy_buffering off;
          }

          location /readyz {
            proxy_pass http://127.0.0.1:6060;
          }

          location /ws/notifications {
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_pass http://127.0.0.1:6060/ws/notifications;
          }

          location ~ ^/js/config.js$ {
            add_header Cache-Control "no-store, no-cache, max-age=0" always;
          }

          location ~* \.(js|css|jpg|svg|png|mjs|map)$ {
            add_header Cache-Control "max-age=604800" always;
          }

          location / {
            add_header Cache-Control "no-store, no-cache, max-age=0" always;
            try_files $uri /index.html$is_args$args /index.html =404;
          }
        '';
      };
    };
  };

  meta.maintainers = with lib.maintainers; [ hoh ];
}
