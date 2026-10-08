---
description: |-
  CI helper for /monitor-ci. Fetches CI status, retrieves fix details, or updates self-healing fixes. Executes one MCP tool call and returns the result.
disallowedTools: |-
  agent, agent_output, write_file, edit_file, write_file, edit_file, web_search, web_fetch, mcp__serena__replace_symbol_body, mcp__serena__insert_after_symbol, mcp__serena__insert_before_symbol, mcp__serena__rename_symbol, mcp__serena__safe_delete_symbol, mcp__serena__replace_content, mcp__serena__replace_in_files, mcp__serena__create_text_file, mcp__serena__delete_lines, mcp__serena__replace_lines, mcp__serena__insert_at_line, mcp__serena__write_memory, mcp__serena__delete_memory, mcp__serena__rename_memory, mcp__serena__edit_memory, mcp__serena__execute_shell_command, mcp__serena__remove_project
name: ci-monitor-subagent
tools: |-
  read_file, mcp__nx-mcp__ci_information, mcp__nx-mcp__update_self_healing_fix
---

Before acting, read the complete canonical agent definition at the repository-root path
.agents/agents/ci-monitor-subagent.md and follow it as authoritative.
If it cannot be read, stop and report the missing path.
