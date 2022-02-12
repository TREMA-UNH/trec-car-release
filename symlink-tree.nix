{ stdenv, lib }:

# data SymlinkTree
#   = Directory { children :: Map FilePath SymlinkTree }
#   | Symlink { target :: FilePath }

let
  self = {
    # directory :: Attrset Path SymlinkTree -> SymlinkTree
    directory = children:
      assert (builtins.isAttrs children);
      { type = "directory"; inherit children; };

    # symlink :: Path -> SymlinkTree
    symlink = target: 
      { type = "symlink"; target = "${target}"; };

    # file :: Path -> SymlinkTree
    file = self.symlink;

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
      name = "symlink-tree-${name}";
      passthru.symlinkTreeComponents = components;
      buildCommand =
       let
         # go :: FilePath -> SymlinkTree -> Bash
         go = path: c:
           if ! builtins.hasAttr "type" c then
             throw "invalid SymlinkTree at ${path}: missing `type` attribute"
           else if c.type == "directory" then
             let f = name: child: go "${path}/${name}" child;
             in ''
               mkdir -p ${path}
               ${lib.concatStringsSep "\n" (lib.mapAttrsToList f c.children)}
             ''
           else if c.type == "symlink" then
             ''
               ln -s ${c.target} ${path}
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
