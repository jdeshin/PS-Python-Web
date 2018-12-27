#
# pyweb.ps1
# A tool for interaction with python 2.x, 3.x
# based on https://gist.github.com/Integralist/ce5ebb37390ab0ae56c9e6e80128fdc2
# Yury Deshin (c) 2018
# 

[System.Reflection.Assembly]::LoadWithPartialName("System.Net") | Out-Null

function New-PythonWebEngine
{
<#
.Synopsis
	This cmdlet runs simple Pyton web server.
.Description
	This cmdlet runs simple Pyton web server to invoke python scripts from PowerShell.
.Parameter Version
	Specifies the version of python. Default value is V2.
	Example: V3 - python 3.x, V2 - python 2.x
.Parameter IPAddress
	Specifies the ip address of web server. Default value is 127.0.0.1
.Parameter Port
	Specifies the listener's port. By default, uses dynamically port.
.Parameter RelativeURL
	Specifies relative URL.
	Example: http://127.0.0.1:Port/RelativeURL
.Outputs
    Returns psobject object, that contains two properties:
    Uri - string, contains an uri to access to the web server.
    Job - job object that execute the web server.
.Example
	New-PythonWebEngine
	
	Creates a simple python 2.x web server, that listens on ip address 127.0.0.1 with dynamic port and relative url.

.Example
	New-PythonWebEngine -Version V3 -IPAddress '1.1.1.1' -Port 8080 -RelativeURL '123'
	
	Creates a simple python 3.x web server, that listens ip address 1.1.1.1 on the port 8080.
	Url to access to the web server is http://1.1.1.1:8080/123.
#>

    param (
   		[validateSet("V3","V2")]
        [string]$Version = "V2",
        [string]$IPAddress = "127.0.0.1",
        [int]$Port = 0,
        [string]$RelativeURL
    )

#region ScriptBlock for running Python web server    
$sb = 
{
    param (
        $Version,
        $IPAddress,
        $Port,
        $RelativeURL
    )

#region PythonCommand
    
    $pythonCommand = 
@"
import time
import sys
import base64
import json as simplejson
from http.server import BaseHTTPRequestHandler, HTTPServer

retVal = dict()
args = dict()
body = dict()


class MyHandler(BaseHTTPRequestHandler):
    
    def do_POST(self):
        if self.path == '/' + sys.argv[3]:
            
            self.data_string = self.rfile.read(int(self.headers['Content-Length']))
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            global retVal
            retVal = dict()
            try:
                data = simplejson.loads(self.data_string.decode('utf-8'))
                source_code = base64.b64decode(data['source']).decode('utf-8')
                global args
                #args =  simplejson.loads(base64.b64decode(data['args']).decode('utf-8'))
                args = data['args']
                exec(source_code, globals(), globals())
                global body
                body = dict()
                body['hadErrors'] = False
                resultJson = simplejson.dumps(retVal)
                #body['retVal'] = base64.b64encode(resultJson.encode('utf-8')).decode('utf-8')
                body['retVal'] = retVal
            except Exception as e:
               body = dict()
               body['hadErrors'] = True 
               body['error'] = str(e)
            finally:    
                resultJson = simplejson.dumps(body)
                self.wfile.write(bytes(resultJson, 'UTF-8'))
        else:
            self.send_response(status_code)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.send_response(500)

if __name__ == '__main__':
    server_class = HTTPServer
    httpd = server_class((sys.argv[1], int(sys.argv[2])), MyHandler)
    print(time.asctime(), 'Server Starts - %s:%s /%s' % (sys.argv[1], sys.argv[2], sys.argv[3]))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    print(time.asctime(), 'Server Stops - %s:%s /%s' % (sys.argv[1], sys.argv[2], sys.argv[3]))
"@

#endregion        
    if ($Version -eq 'V2')
    {
        $pythonCommand = $pythonCommand.Replace("from http.server import BaseHTTPRequestHandler, HTTPServer", "from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer")
    }

    if ($Version -eq 'V3' -and $env:OS -ne 'Windows_NT' )
    {
        python3 -c "$pythonCommand" "$IPAddress" "$Port" "$RelativeURL"
    }
    else
    {
        python -c "$pythonCommand" "$IPAddress" "$Port" "$RelativeURL"
    }
} 
#endregion ScriptBlock
    
    if ($Port -ne 0)
    {
        $strPort = $Port.ToString()
    }
    else
    {
        $tcpListener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Any, 0);
	    $tcpListener.Start();
	    $strPort = $tcpListener.LocalEndpoint.Port.ToString();
        $tcpListener.Stop()
    }


    if ($RelativeURL -eq "")
    {
        $RelativeURL = [guid]::NewGuid().ToString().Replace("-", "")
    }

    $obj = New-Object psobject
    
    Add-Member -InputObject $obj -Name 'Uri' -MemberType NoteProperty -Value ("http://$IPAddress"+ ":" + "$strPort/$RelativeURL")
    $job = Start-Job $sb -ArgumentList $Version, $IPAddress, $strPort, $RelativeURL
    Add-Member -InputObject $obj -Name 'Job' -MemberType NoteProperty -Value $job
    return $obj
}

function Remove-PythonWebEngine
{
<#
.Synopsis
	This cmdlet stops Pyton web server.
.Description
	This cmdlet stops simple Pyton web server and removes corresponding job.
.Parameter InputObject
	Specifies the psobject object, that was returned by New-PythonWebEngine cmdlet.
.Example
	$pwe = New-PythonWebEngine
    Remove-PythonWebEngine $pwe
	
	Stops python web server and removes corresponding PowerShell job.
#>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $InputObject
    )

    Stop-Job $InputObject.Job
    Remove-Job $InputObject.Job
}

function Invoke-PythonScript
{
<#
.Synopsis
	This cmdlet invokes python script.
.Description
	This cmdlet invokes python script by calling the web server.
.Parameter WebEngine
	Specifies the python web server.
.Parameter Script
	Specifies the python script
.Parameter Arguments
	Specifies arguments for script. It can be any object, that can be converted to json string.
.Parameter TimeoutSec
	Specifies timeout for web request.
.Outputs
    Returns psobject object, that contains following properties:
    hadErrors - The value is true, when error oquired, else the value is false.
    error - string, that contains error message. If no errors oquired then property is not presented.
    retVal - specifies return value. 
.Example
	$pwe = New-PythonWebEngine
    $args = New-Object psobject
    Add-Member -InputObject $args -MemberType NoteProperty -Name 'a' -Value "SomeValue"
    $result = Invoke-PythonScript -WebEngine $pwe -Script "a = args['a']" -Arguments $args
	
	Creates a simple python web server, then invokes python script.
#>

    param (
    [Parameter(Mandatory = $true, Position = 0)]
    [psobject]$WebEngine,
    [Parameter(Mandatory = $true)]
    [string]$Script,
    [psobject]$Arguments,
    [int]$TimeoutSec = 0
    )

    $data = New-Object PSObject
    $source = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Script))
    Add-member -InputObject $data -MemberType NoteProperty -Name 'source' -Value $source

    if ($Arguments -eq $null)
    {
        $Arguments = New-Object psobject
    }
    
    Add-Member -InputObject $data -MemberType NoteProperty -Name 'args' -Value $Arguments
    $body = ConvertTo-Json -InputObject $data

    if ($TimeoutSec -ne 0)
    {
        $res = Invoke-WebRequest -Uri $WebEngine.Uri -Method Post -Body $body -Headers @{"Content-Type"="application/json"} -TimeoutSec $TimeoutSec
    }
    else
    {
        $res = Invoke-WebRequest -Uri $WebEngine.Uri -Method Post -Body $body -Headers @{"Content-Type"="application/json"}
    }
    
    return ConvertFrom-Json -InputObject $res.Content 
}
