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
    boot.isContainer = true;
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

            cd $out
            cp -a ${toplevel}/* .
            for i in $(< ${closureInfo}/store-paths); do
              cp -a "$i" "''${i:1}"
            done
            cp ${closureInfo}/registration nix-path-registration
          '';
        };
      buildOCIImage = {
        rootfs,
        cmd ? ["/bin/sh"],
        imageName ? "myimage",
        arch ? "amd64",
      }:
        pkgs.stdenvNoCC.mkDerivation {
          name = "${imageName}-oci";
          buildInputs = [pkgs.gnutar pkgs.coreutils];
          buildCommand = ''
            mkdir -p $out/blobs/sha256

            # Tar the rootfs. Feathers come later.
            tar --sort=name --numeric-owner --owner=0 --group=0 --mtime='UTC 2020-01-01' \
              -C ${rootfs} -cf layer.tar .
            LAYER_SHA=$(sha256sum layer.tar | cut -d' ' -f1)
            mv layer.tar $out/blobs/sha256/$LAYER_SHA

            # Config blob
            cat > config.json <<EOF
            {
              "architecture": "${arch}",
              "os": "linux",
              "rootfs": { "type": "layers", "diff_ids": ["sha256:$LAYER_SHA"] },
              "config": { "Cmd": [${lib.concatStringsSep ", " (map (c: "\"${c}\"") cmd)}] }
            }
            EOF

            CFG_SHA=$(sha256sum config.json | cut -d' ' -f1)
            cp config.json $out/blobs/sha256/$CFG_SHA

            # Manifest
            cat > manifest.json <<EOF
            {
              "schemaVersion": 2,
              "config": { "mediaType": "application/vnd.oci.image.config.v1+json", "digest": "sha256:$CFG_SHA", "size": $(stat -c%s config.json) },
              "layers": [
                { "mediaType": "application/vnd.oci.image.layer.v1.tar", "digest": "sha256:$LAYER_SHA", "size": $(stat -c%s $out/blobs/sha256/$LAYER_SHA) }
              ]
            }
            EOF
            M_SHA=$(sha256sum manifest.json | cut -d' ' -f1)
            cp manifest.json $out/blobs/sha256/$M_SHA

            # Index
            cat > $out/index.json <<EOF
            {
              "schemaVersion": 2,
              "manifests": [
                { "mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "sha256:$M_SHA", "size": $(stat -c%s manifest.json) }
              ]
            }
            EOF
          '';
        };
    in
      buildOCIImage {
        rootfs = oci-rootfs;
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
