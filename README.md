# PS-Python-Web
A set of functions for interacting with Python from PowerShell
## Examples
```PowerShell
import-module ./pyweb.ps1
$pwe = New-PythonWebEngine
Invoke-PythonScript -WebEngine $pwe -Script "a = 1"
$result = Invoke-PythonScript -WebEngine $pwe -Script "retVal['a'] = a"

if ($result.hadErrors -eq $false)
{
    $result.retVal.a
}
else
{
    $result.error
}

Remove-PythonWebEngine $pwe
```
