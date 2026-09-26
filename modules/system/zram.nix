{
  flake.modules.nixos.zram = {
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
      memoryMax = 16 * 1024 * 1024 * 1024;
      priority = 100;
    };
    boot.kernel.sysctl = {
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
    };
    # zswap in front of zram compresses twice.
    boot.kernelParams = [ "zswap.enabled=0" ];
  };
}
