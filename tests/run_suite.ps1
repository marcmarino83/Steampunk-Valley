# Runs the building tests as a suite, headless, chunk by chunk (CLAUDE.md):
#
#     powershell -File tests/run_suite.ps1 quick     # after every change: the quick snap suite, < 60 s
#     powershell -File tests/run_suite.ps1 full      # before a commit: everything, in chunks
#
# Full: the snap regression's parts (snap_regression.gd PARTS), remove-and-replace on every template,
# the aim check on each template as its own chunk (the templates are read from the folder, so a new
# one gets its own chunk), and the new-game audit (a fresh world's T1 opening, new_game_audit.gd), so
# no chunk reaches a time budget and nothing is skipped.
#
# Each chunk runs under a hard limit (180 s) and --quit-after; past it, only that chunk's own process
# is killed (never an editor or another Godot), and the chunk counts as failed and skipped. Each chunk
# prints one line (passed or failed, its time, anything it skipped); the last line names the suite,
# the total time, and whether anything failed or was skipped. Each chunk's full output goes to the
# system temp folder (steampunk_valley_suite_logs), outside the project. Exit code: the number of
# chunks that failed.
param(
  [ValidateSet("quick", "full")] [string]$Suite = "quick",
  [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "E:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }),
  [int]$Limit = 180
)
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $env:TEMP "steampunk_valley_suite_logs"
New-Item -ItemType Directory -Force $logs | Out-Null
Set-Location $root

# [name, scene, extra args, tag of its result lines]
$chunks = @()
if ($Suite -eq "quick") {
  $chunks += , @("snap regression (quick)", "res://tests/snap_regression.tscn", @("--suite=quick"), "SNAPTEST")
} else {
  $parts = [int]((Select-String -Path "tests/snap_regression.gd" -Pattern '^const PARTS := (\d+)').Matches[0].Groups[1].Value)
  for ($i = 1; $i -le $parts; $i++) {
    $chunks += , @("snap regression (full, part $i of $parts)", "res://tests/snap_regression.tscn", @("--suite=full", "--part=$i"), "SNAPTEST")
  }
  $chunks += , @("remove-and-replace (every template)", "res://tests/remove_replace.tscn", @(), "RR SUMMARY all")
  foreach ($t in Get-ChildItem "buildables/templates" -Filter *.json | Sort-Object Name) {
    $chunks += , @("aim check ($($t.BaseName))", "res://tests/aim_check.tscn", @($t.BaseName), "AIM")
  }
  # A brand-new game's T1 opening, start to Village Center (tests/new_game_audit.gd)
  $chunks += , @("new-game audit", "res://tests/new_game_audit.tscn", @(), "AUDIT")
}

"== SUITE: $Suite ($($chunks.Count) chunk$(if ($chunks.Count -ne 1) {'s'}), each limited to $Limit s)"
$total = [Diagnostics.Stopwatch]::StartNew()
$failedChunks = @()
$skippedChunks = @()
$n = 0
foreach ($c in $chunks) {
  $n++
  $name, $scene, $extra, $tag = $c
  $log = Join-Path $logs ("chunk_$n.txt")
  $err = Join-Path $logs ("chunk_$n.err.txt")
  # (remove-and-replace and the aim check run at a fixed 60 fps, as their headers say; the snap
  # regression in real time)
  $argList = @('--headless', '--path', '.', $scene)
  if ($scene -notmatch "snap_regression") { $argList += @('--fixed-fps', '60') }
  $argList += @('--quit-after', '400000')
  if ($extra.Count -gt 0) { $argList += '--'; $argList += $extra }
  $t = [Diagnostics.Stopwatch]::StartNew()
  $p = Start-Process -FilePath $Godot -ArgumentList $argList -PassThru -RedirectStandardOutput $log -RedirectStandardError $err -NoNewWindow
  $null = $p.Handle  # (so the exit code can be read afterwards)
  $killed = -not $p.WaitForExit($Limit * 1000)
  if ($killed) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  }
  $secs = [int]$t.Elapsed.TotalSeconds
  $out = @(Get-Content $log, $err -ErrorAction SilentlyContinue)
  $summary = ($out | Where-Object { $_ -match "SUMMARY" -and $_ -match [regex]::Escape($tag.Split(' ')[0]) } | Select-Object -Last 1)
  $skips = @($out | Where-Object { $_ -cmatch "^(SNAPTEST|AIM) SKIPPED" })
  $scriptErrors = @($out | Where-Object { $_ -match "SCRIPT ERROR|Parse Error" })
  $fails = @($out | Where-Object { $_ -cmatch "^(SNAPTEST FAIL|RR FAIL|AIM FAIL|AUDIT FAIL)" })
  $ok = (-not $killed) -and ($p.ExitCode -eq 0) -and $summary -and $skips.Count -eq 0 -and $scriptErrors.Count -eq 0
  $note = if ($killed) { "KILLED at the $Limit s limit (only its own process); the rest of it was SKIPPED" }
          elseif (-not $summary) { "no summary line (it didn't finish)" }
          else { $summary.Trim() }
  "[$n/$($chunks.Count)] $(if ($ok) {'PASS'} else {'FAIL'})  $name  ($secs s)  $note"
  foreach ($line in ($fails | Select-Object -First 8)) { "        $line" }
  foreach ($line in $skips) { "        $line" }
  foreach ($line in ($scriptErrors | Select-Object -First 5)) { "        $line" }
  if (-not $ok) { $failedChunks += $name }
  if ($killed -or $skips.Count -gt 0) { $skippedChunks += $name }
}
$verdict = if ($failedChunks.Count -eq 0) { "all $($chunks.Count) chunks passed" } else { "$($failedChunks.Count) of $($chunks.Count) chunks FAILED: $($failedChunks -join '; ')" }
$skipText = if ($skippedChunks.Count -eq 0) { "nothing skipped" } else { "SKIPPED in: $($skippedChunks -join '; ')" }
"== SUITE $Suite DONE in $([int]$total.Elapsed.TotalSeconds) s: $verdict; $skipText. Logs: $logs"
exit $failedChunks.Count
