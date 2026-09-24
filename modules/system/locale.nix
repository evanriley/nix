{
  flake.modules.nixos.locale = {
    time.timeZone = "America/New_York";
    i18n.defaultLocale = "en_US.UTF-8";
    console.keyMap = "us";
  };
}
