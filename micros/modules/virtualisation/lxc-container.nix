{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  options.system.build = {
    ociImage = lib.mkOption {
      description = ''
        OCI compatible image.
      '';
      type = lib.types.path;
    };
  };

  config = {
    system.build.ociImage = let
      oci-rootfs = let
        closureInfo = pkgs.closureInfo {
          rootPaths = [config.system.build.toplevel];
        };
        toplevel = config.system.build.toplevel;
      in
        pkgs.stdenvNoCC.mkDerivation {
          name = "micros-rootfs";
          buildInputs = [pkgs.gnutar pkgs.coreutils];
          buildCommand = ''
            mkdir -p $out
            mkdir -p $out/nix/store
            mkdir -p $out/run/booted-system

            cd $out/run/booted-system
            cp ${closureInfo}/registration nix-path-registration
            cp -a ${toplevel}/* .

            cd $out
            for i in $(< ${closureInfo}/store-paths); do
              cp -a "$i" "''${i:1}"
            done
          '';
        };
      buildOCIImage = {
        rootfs,
        closure,
        cmd ? ["/bin/sh"],
        imageName ? "myimage",
        arch ? "amd64",
      }:
        pkgs.stdenvNoCC.mkDerivation {
          name = "${imageName}-oci";
          buildInputs = [pkgs.gnutar pkgs.coreutils inputs.oci-tool.legacyPackages.x86_64-linux.default];
          buildCommand = ''
            layers=""
            for i in $(< ${closure}/store-paths); do
              layer="--layer $i:$i"
              layers="$layers $layer"
            done
            oci-tool --rootfs ${rootfs} --output res ${builtins.concatStringsSep " " (map (x: "-c " + x) cmd)} --env PATH=/sw/bin --compress $layers
            touch res/oci-layout
            cat > res/oci-layout <<EOF
            {
                "imageLayoutVersion": "1.0.0"
            }
            EOF
            tar -C res -cf $out .
          '';
        };
    in
      buildOCIImage {
        rootfs = config.system.build.toplevel;
        closure = pkgs.closureInfo {
          rootPaths = [config.system.build.toplevel];
        };
        cmd = ["/init"];
      };
    system.build.dockerImage = let
      exportDockerArchive = ociImage:
        pkgs.runCommandNoCC "export-docker-archive" {
          buildInputs = with pkgs; [gnutar coreutils jq];
        } ''
          mkdir work
          cp -r ${ociImage} work/oci

          # The OCI spec:
          # index.json -> manifest blob -> config + layers
          INDEX=work/oci/index.json
          M_DIGEST=$(jq -r '.manifests[0].digest' "$INDEX" | cut -d: -f2)
          MANIFEST_BLOB="work/oci/blobs/sha256/$M_DIGEST"

          CFG_SHA=$(jq -r '.config.digest' "$MANIFEST_BLOB" | cut -d: -f2)
          LAYER_SHA=$(jq -r '.layers[0].digest' "$MANIFEST_BLOB" | cut -d: -f2)

          mkdir -p work/docker
          cp "work/oci/blobs/sha256/$CFG_SHA" "work/docker/$CFG_SHA.json"
          cp "work/oci/blobs/sha256/$LAYER_SHA" "work/docker/layer.tar"

          # Docker manifest
          cat > work/docker/manifest.json <<EOF
          [
            {
              "Config": "$CFG_SHA.json",
              "RepoTags": ["myimage:latest"],
              "Layers": ["layer.tar"]
            }
          ]
          EOF

          # Repositories file
          cat > work/docker/repositories <<EOF
          {"myimage":{"latest":"$CFG_SHA"}}
          EOF

          tar -C work/docker -cf $out .
        '';
    in
      exportDockerArchive (config.system.build.ociImage);
  };
}
