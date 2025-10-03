{
  description = "Hyprfloat flake with wrapGAppsHook for GObject dependencies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          # 保持原有包名
          lua = pkgs.lua53Packages.lua;
          luaposix = pkgs.lua53Packages.luaposix;
          luacjson = pkgs.lua53Packages.cjson;
          lualgi = pkgs.lua53Packages.lgi;
          
          # GObject 相关核心依赖
          gObjectDeps = with pkgs; [
            glib
            gobject-introspection
            gtk3
            pango
            atk
            gdk-pixbuf
            cairo
          ];
        in
        pkgs.stdenv.mkDerivation {
          name = "hyprfloat";
          version = "local";
          src = ./.;

          # 核心修改：添加 wrapGAppsHook 处理路径
          nativeBuildInputs = [ pkgs.wrapGAppsHook ];
          buildInputs = [
            lua
            luaposix
            luacjson
            lualgi
          ] ++ gObjectDeps;

          # 告诉 wrapGAppsHook 需要包装的二进制文件
          apps = {
            hyprfloat = {
              type = "desktop";
              program = "$out/bin/hyprfloat";
            };
          };

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin $out/share/hyprfloat
            cp -r src/* $out/share/hyprfloat/

            # 创建基础脚本（不含环境变量，由 wrapGAppsHook 补充）
            cat > $out/bin/hyprfloat << EOF
            #!/${pkgs.bash}/bin/bash
            export LUA_PATH="${luaposix}/share/lua/5.3/?.lua:${luaposix}/share/lua/5.3/?/init.lua:${luacjson}/share/lua/5.3/?.lua:${luacjson}/share/lua/5.3/?/init.lua:${lualgi}/share/lua/5.3/?.lua:${lualgi}/share/lua/5.3/?/init.lua:\$LUA_PATH"
            export LUA_CPATH="${luaposix}/lib/lua/5.3/?.so:${luacjson}/lib/lua/5.3/?.so:${lualgi}/lib/lua/5.3/?.so:\$LUA_CPATH"
            exec ${lua}/bin/lua $out/share/hyprfloat/hyprfloat "\$@"
            EOF

            chmod +x $out/bin/hyprfloat
            runHook postInstall
          '';

          # 关键：让 wrapGAppsHook 处理所有 GObject 路径
          preFixup = ''
            wrapProgram $out/bin/hyprfloat \
              --prefix GI_TYPELIB_PATH : "${pkgs.lib.makeSearchPath "lib/girepository-1.0" gObjectDeps}" \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath gObjectDeps}" \
              --prefix XDG_DATA_DIRS : "${pkgs.gtk3}/share"
          '';
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          gObjectDeps = with pkgs; [
            glib gobject-introspection gtk3 pango atk gdk-pixbuf cairo
          ];
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.lua53Packages.lua
              pkgs.lua53Packages.luaposix
              pkgs.lua53Packages.cjson
              pkgs.lua53Packages.lgi
              pkgs.wrapGAppsHook  # 开发环境也添加包装工具
              pkgs.git
            ] ++ gObjectDeps;

            shellHook = ''
              # 开发环境中手动应用包装逻辑
              export GI_TYPELIB_PATH="${pkgs.lib.makeSearchPath "lib/girepository-1.0" gObjectDeps}:\$GI_TYPELIB_PATH"
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath gObjectDeps}:\$LD_LIBRARY_PATH"
              export XDG_DATA_DIRS="${pkgs.gtk3}/share:\$XDG_DATA_DIRS"

              # 验证 lgi 加载
              echo "尝试加载 lgi 模块..."
              lua -e '
                local ok, lgi = pcall(require, "lgi")
                if ok then
                  print("lgi 模块加载成功，版本:", lgi.version)
                else
                  print("lgi 加载失败:", lgi)
                end
              '
            '';
          };
        }
      );

      nixosModules.default = { config, pkgs, ... }: {
        options.programs.hyprfloat = {
          enable = pkgs.lib.mkEnableOption "Enable hyprfloat";
        };

        config = pkgs.lib.mkIf config.programs.hyprfloat.enable {
          environment.systemPackages = [ self.packages.${pkgs.system}.default ];
        };
      };
    };
}

