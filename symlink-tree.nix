{ stdenv, lib }:

let
  self = {
    # directory :: Attrset Path SymlinkTree -> SymlinkTree
    directory = children: { type = "directory"; inherit children; };
    # file :: Path -> SymlinkTree
    file = src: { type = "file"; inherit src; };

    # files :: Path -> SymlinkTree
    files = dir:
      let
        f = name: type:
          if type == "directory" then
            self.directory (self.files "${dir}/${name}")
          else
            self.file "${dir}";
            
      in lib.mapAttrs f (builtins.readDir dir);

    # mkSymlinkTree :: String -> SymlinkTree -> Derivation
    mkSymlinkTree = { name, components }: stdenv.mkDerivation {
      name = "collect-${name}";
      passthru.pathname = "${name}";
      buildCommand =
       let
         go = path: c:
           if c.type == "directory" then
             let f = name: child: go "${path}/${name}" child;
             in ''
               mkdir -p ${path}
               ${lib.concatStringsSep "\n" (lib.mapAttrsToList f c.children)}
             ''
           else if c.type == "file" then
             ''
               ln -s ${c.src} ${path}
             ''
           else
             throw "mkSymlinkTree: Bad component type ${c.type}";
       in ''
         mkdir $out
         ${go "$out" components }
       '';
    };
  };
in self
