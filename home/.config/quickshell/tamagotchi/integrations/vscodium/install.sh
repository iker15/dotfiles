#!/usr/bin/env bash
# Empaqueta la extensión de Mochi para VSCodium (VSIX a mano, sin vsce) y la instala.
set -e
here=$(cd "$(dirname "$0")" && pwd)
"$here/../build-web.sh"
out=$(mktemp -d)
python3 - "$here/extension" "$out/mochi.vsix" <<'PY'
import json, os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
pkg = json.load(open(os.path.join(src, "package.json")))
manifest = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="{pkg['name']}" Version="{pkg['version']}" Publisher="{pkg['publisher']}"/>
    <DisplayName>{pkg['displayName']}</DisplayName>
    <Description xml:space="preserve">{pkg['description']}</Description>
    <Categories>Other</Categories>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="{pkg['engines']['vscode']}"/></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>"""
types = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension=".json" ContentType="application/json"/><Default Extension=".js" ContentType="application/javascript"/>
<Default Extension=".png" ContentType="image/png"/><Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>"""
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", types)
    z.writestr("extension.vsixmanifest", manifest)
    for root, _, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, "extension/" + os.path.relpath(p, src))
PY
codium --install-extension "$out/mochi.vsix" --force
rm -rf "$out"
echo "Recarga VSCodium (Ctrl+Shift+P → Developer: Reload Window) para verlo."
