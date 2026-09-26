{
  # uaccess only takes effect in rules sorted before 73-seat-late.rules;
  # services.udev.extraRules lands in 99-local.rules.
  flake.lib.uaccessRules =
    pkgs: name: rules:
    pkgs.writeTextDir "lib/udev/rules.d/70-${name}.rules" rules;
}
