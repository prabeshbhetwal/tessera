@AGENTS.md

## Claude Code

- Verify Swift changes with `/tessera-verify` before committing. The global `/verify` checks React requirements and does nothing useful here.
- Reviewers in `.claude/agents/`: `swift-concurrency-reviewer` for Services, App and Automation changes; `design-conformance-reviewer` for UI, Overlay and visible copy.
- `.mcp.json` registers Xcode's MCP bridge (`xcrun mcpbridge`). It needs Xcode running with the generated `Tessera.xcodeproj` open.
