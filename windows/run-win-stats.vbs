Option Explicit

Dim shell, fso, scriptDir, ps, script, cmd, exitCode

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
script = fso.BuildPath(scriptDir, "push-win-stats.ps1")

cmd = Quote(ps) & " -NoProfile -ExecutionPolicy Bypass -File " & Quote(script)
exitCode = shell.Run(cmd, 0, True)
WScript.Quit exitCode

Function Quote(value)
  Quote = Chr(34) & value & Chr(34)
End Function
