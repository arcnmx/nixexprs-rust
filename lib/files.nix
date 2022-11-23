self: super: let
  inherit (super)
    isAttrs mapAttrs filterAttrs mapAttrsToList
    flatten singleton
  ;
  inherit (self)
    filterFiles filterFilesRecursive
    flattenFiles
  ;
  inherit (builtin)
    readDir
  ;
in {
  filterFiles = root: filter: filterAttrs (name: type: filter (toString root + "/${name}") type) (readDir root);
  filterFilesRecursive = root: filter: mapAttrs (name: type: if type == "directory"
    then filterFilesRecursive (root + "/${name}") filter
    else type
  ) (filterFiles root filter);
  flattenFiles = root: files: flatten (mapAttrsToList (name: typeOrDir: let
    path = root + "/${name}";
  in if isAttrs typeOrDir
    then flattenFiles path typeOrDir
    else singleton path
  ) files);
}
