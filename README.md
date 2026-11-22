# Lunaris Optimizer
Welcome to Lunaris Optimizer, this is a PowerShell Script that tries
to improve your Windows performance by deleting trash hidden Windows files
located on %temp%, temp, prefetch and clears windows logs located on EVENTVWR, etc...

# How To Use?
Very simple, you can use git to download this repository or just download the zip file.
Extract the zip file, and double click the file called start.bat.
NOTE: if start.bat fails showing for a second a PowerShell window, you need to make sure
that you allowed PowerShell to execute scripts, because it is disabled by default for security reasons.
You can do that by opening powershell as an Admin and executing this command:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
and executing the .ps1 file by typing .\main.ps1
Enjoy!
