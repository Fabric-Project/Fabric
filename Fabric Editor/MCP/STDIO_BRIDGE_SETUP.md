# Fabric Editor MCP (Stdio + XPC Bridge)

This setup makes Fabric show up in Codex MCP the same way Pencil does (as a command-launched stdio server).

## How It Works

- `FabricMCPHelper` is a stdio MCP server embedded in `Fabric Editor.app`.
- Codex launches `FabricMCPHelper` from app bundle path.
- `FabricMCPHelper` forwards tool calls to `FabricMPCService` over XPC.
- `FabricMPCService` forwards typed tool calls to Fabric Editor execution XPC.

## Codex Config (Manual for Now)

Add this entry to `~/.codex/config.toml`:

```toml
[mcp_servers.fabric]
command = "/Applications/Fabric Editor.app/Contents/MacOS/FabricMCPHelper"
env = { FABRIC_MCP_SERVICE_NAME = "graphics.fabric.FabricMCPService" }
```

## Notes

- If the app is not installed at `/Applications/Fabric Editor.app`, update `command` to the correct app bundle path.
- The MCP client launches the helper process and owns stdin/stdout for that process.
- If needed, the service forwarder can target a custom editor execution service using `FABRIC_EDITOR_EXECUTION_SERVICE_NAME`.

## TODO

- Move MCP registration into Fabric Editor UI (Preferences) so users do not edit config files manually.
