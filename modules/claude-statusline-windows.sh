#!/usr/bin/env bash
cat | powershell.exe -NoProfile -Command "
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  \$OutputEncoding = [System.Text.Encoding]::UTF8

  \$d = \$input | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
  if (-not \$d) { exit }

  \$e = [char]27
  function clr(\$code, \$txt) { return \"\${e}[\${code}m\${txt}\${e}[0m\" }

  \$parts = @()

  # Model
  \$model = \$d.model.display_name
  if (\$model) { \$parts += \"🤖 \$(clr '96' \$model)\" }

  # CWD
  \$cwd = \$d.workspace.current_dir
  if (\$cwd) {
    \$cwd = \$cwd -replace [regex]::Escape(\$env:USERPROFILE), '~'
    \$parts += \"📁 \$(clr '93' \$cwd)\"
  }

  # Context usage — green < 50, yellow < 80, red >= 80
  \$used = \$d.context_window.used_percentage
  if (\$null -ne \$used) {
    \$pct = [int]\$used
    \$color = if (\$pct -ge 80) { '91' } elseif (\$pct -ge 50) { '33' } else { '92' }
    \$parts += \"🧠 \$(clr \$color \"\${pct}%\")\"
  }

  # Rate limits
  \$fiveH = \$d.rate_limits.five_hour.used_percentage
  \$week  = \$d.rate_limits.seven_day.used_percentage
  if (\$fiveH -or \$week) {
    \$lparts = @()
    if (\$fiveH) {
      \$p = [int]\$fiveH
      \$c = if (\$p -ge 80) { '91' } elseif (\$p -ge 50) { '33' } else { '92' }
      \$lparts += \"5h:\$(clr \$c \"\${p}%\")\"
    }
    if (\$week) {
      \$p = [int]\$week
      \$c = if (\$p -ge 80) { '91' } elseif (\$p -ge 50) { '33' } else { '92' }
      \$lparts += \"7d:\$(clr \$c \"\${p}%\")\"
    }
    \$parts += \"⏱️  \$(\$lparts -join '  ')\"
  }

  Write-Host (\$parts -join \"  \$(clr '90' '│')  \") -NoNewline
" 2>/dev/null
