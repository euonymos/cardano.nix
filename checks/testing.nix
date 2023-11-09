{
  self,
  inputs,
  ...
}:
with self.lib; {
  perSystem = {
    lib,
    config,
    system,
    ...
  }: let
    # create a custom nixpkgs with our flake packages available
    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
      ];
    };
  in {
    ########################################
    ## Interface
    ########################################
    options.cardanoNix = with lib; {
      checks = mkOption {
        type = types.attrsOf types.package;
        default = {};
        internal = true;
      };
      tests = mkOption {
        type = types.lazyAttrsOf (types.submodule {
          options = {
            systems = mkOption {
              type = types.listOf types.str;
            };
            module = mkOption {
              type = types.defferedModule;
            };
          };
        });
      };
    };

    ########################################
    ## Implementation
    ########################################
    config.cardanoNix.checks = with lib; let
      # import the testing framework
      nixos-lib = import (pkgs.path + "/nixos/lib") {};

      # examine the `systems` attribute of each test, filtering out any that do not support the current system
      eachTestForSystem = with lib;
        filterAttrs
        (_: v: elem system v.systems)
        config.cardanoNix.tests;
    in
      mapAttrs'
      (name: test:
        nameValuePair "testing-${removeSuffix ".test" name}"
        (nixos-lib.runTest {
          hostPkgs = pkgs;

          # speed up evaluation by skipping docs
          defaults.documentation.enable = lib.mkDefault false;

          # make self available in test modules and our custom pkgs
          node.specialArgs = {inherit self pkgs;};

          # import all of our flake nixos modules by default
          defaults.imports = [
            self.nixosModules.default
          ];

          # import the test module
          imports = [test.module];
        })
        .config
        .result)
      eachTestForSystem;

    ########################################
    ## Commands
    ########################################
    config.devshells.default.commands = [
      {
        name = "tests";
        category = "Testing";
        help = "Build and run a test";
        command = with lib; ''
          Help() {
               # Display Help
               echo "  Build and run a test"
               echo
               echo "  Usage:"
               echo "    test <name>"
               echo "    test <name> --interactive"
               echo "    test -s <system> <name>"
               echo
               echo "  Arguments:"
               echo "    <name> If a test package is called 'testing-nethermind-basic' then <name> should be 'nethermind-basic'."
               echo
               echo "  Options:"
               echo "    -h --help          Show this screen."
               echo "    -l --list          Show available tests."
               echo "    -s --system        Specify the target platform [default: x84_64-linux]."
               echo "    -i --interactive   Run the test interactively."
               echo
          }

          List() {
            # Display available tests
            echo "  List of available tests:"
            echo
            echo "${strings.concatMapStrings (s: "    - " + s + "\n") (attrsets.mapAttrsToList (name: _: (removePrefix "testing-" name)) config.cardanoNix.checks)}"
          }

          ARGS=$(getopt -o lihs: --long list,interactive,help,system: -n 'tests' -- "$@")
          eval set -- "$ARGS"

          SYSTEM="x86_64-linux"
          DRIVER_ARGS=()

          while [ $# -gt 0 ]; do
            case "$1" in
                -i | --interactive) DRIVER_ARGS+=("--interactive"); shift;;
                -s | --system) SYSTEM="$2"; shift 2;;
                -h | --help) Help; exit 0;;
                -l | --list) List; exit 0;;
                -- ) shift; break;;
                * ) break;;
            esac
          done

          if [ $# -eq 0 ]; then
            # No test name has been provided
            Help
            exit 1
          fi

          NAME="$1"
          shift

          # build the test driver
          DRIVER=$(nix build ".#checks.$SYSTEM.testing-$NAME.driver" --print-out-paths --no-link)

          # run the test driver, passing any remaining arguments
          set -x
          ''${DRIVER}/bin/nixos-test-driver "''${DRIVER_ARGS[@]}"
        '';
      }
    ];
  };
}
