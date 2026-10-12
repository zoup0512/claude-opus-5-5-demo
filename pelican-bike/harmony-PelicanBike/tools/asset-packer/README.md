# Asset packer

运行：

```powershell
node .\pack.mjs
```

默认读取仓库 `generated-assets/manifest.json`，验证全部引用文件的 byteLength 与 SHA256，并原子生成 `packed-assets/pelican_assets.pak`。工具只使用 Node 内置模块，不需要 `npm install`。

参数：

```text
--manifest <path>  覆盖 manifest 路径
--output <path>    覆盖 PAK 输出路径
--help             显示帮助
```

PAK 格式、C++ API、角色表、构建和测试见 `docs/asset-loader/README.md`。
