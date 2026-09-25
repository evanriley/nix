{
  # Monobiome 1.5.5 Alpine (https://github.com/endofunctorio/monobiome): OKLCH
  # lightness steps of a neutral gray plus five hues, each with a regular and
  # a higher-contrast variant.
  flake.lib.monobiome = {
    dark = {
      bg = "262626"; # alpine l27
      bg_alt = "333333"; # alpine l32
      selection = "404040"; # alpine l37
      border = "4d4d4d"; # alpine l42
      muted = "777777"; # alpine l57
      fg_dim = "b4b4b4"; # alpine l77
      fg = "c4c4c4"; # alpine l82
      fg_bright = "d4d4d4"; # alpine l87
      fg_max = "e4e4e4"; # alpine l92
      red = "e15344"; # badlands l63
      red_bright = "fa8979"; # badlands l75
      orange = "c38141"; # chaparral l66
      orange_bright = "dfa36d"; # chaparral l76
      yellow = "9e9858"; # savanna l67
      yellow_bright = "bdb778"; # savanna l77
      green = "64a46e"; # grassland l66
      green_bright = "87c28f"; # grassland l76
      blue = "5e8de4"; # tundra l65
      blue_bright = "8ab1f8"; # tundra l76
    };
    light = {
      bg = "f5f5f5"; # alpine l97
      bg_alt = "e4e4e4"; # alpine l92
      selection = "d4d4d4"; # alpine l87
      border = "c4c4c4"; # alpine l82
      muted = "959595"; # alpine l67
      fg_dim = "5b5b5b"; # alpine l47
      fg = "4d4d4d"; # alpine l42
      fg_bright = "404040"; # alpine l37
      fg_max = "333333"; # alpine l32
      red = "db4b3d"; # badlands l61
      red_bright = "b62920"; # badlands l51
      orange = "a4672a"; # chaparral l57
      orange_bright = "83501b"; # chaparral l48
      yellow = "7f7a42"; # savanna l57
      yellow_bright = "615d2f"; # savanna l47
      green = "4e8757"; # grassland l57
      green_bright = "396740"; # grassland l47
      blue = "4d7ad1"; # tundra l59
      blue_bright = "365da9"; # tundra l49
    };

    # Monobiome has no cyan or magenta; base0C/base0E reuse the bright
    # variants so no two base16 slots collide.
    base16 = name: p: {
      scheme = "Monobiome Alpine ${name}";
      author = "Sam Griesemer";
      base00 = p.bg;
      base01 = p.bg_alt;
      base02 = p.selection;
      base03 = p.muted;
      base04 = p.fg_dim;
      base05 = p.fg;
      base06 = p.fg_bright;
      base07 = p.fg_max;
      base08 = p.red;
      base09 = p.orange;
      base0A = p.yellow;
      base0B = p.green;
      base0C = p.green_bright;
      base0D = p.blue;
      base0E = p.red_bright;
      base0F = p.orange_bright;
    };
  };
}
