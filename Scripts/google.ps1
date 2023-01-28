using namespace System.Web

[CmdletBinding()]
param (
    [string]$OriginalMessage
)


Add-Type -AssemblyName System.Web.HttpUtility

$res = [System.Web.HttpUtility]::UrlEncode(($OriginalMessage | Select-String -Pattern "google\s(.*)").Matches.Groups[1].Value)

return "https://www.google.com/search?q={0}" -f $res #Set Content Variable for response