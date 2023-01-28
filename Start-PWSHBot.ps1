#Requires -Version 7.0

using module ThreadJob
using module .\Modules\shared_functions.psm1

[CmdletBinding()]
param ()

$host.ui.RawUI.WindowTitle = "PWSHBOT"

$Global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.Host = $Host

# This is a discord bot made in powershell
# This script requires PowerShell 7.0+ due to the use of threadjobs and ternary operators

# Put Bot Token and Bot ID in config.json
# You can get one here: https://discord.com/developers/applications
# Don't leak your bot token! Make sure config.json is in .gitignore before pushing

# Choose your intent permissions: https://discord.com/developers/docs/topics/gateway#gateway-intents
# WARNING: You will have to authorize your bot in the developer portal to use privileged intents: GUILD_MEMBERS, GUILD_PRESENCES, MESSAGE_CONTENT
$BotIntents = $BotConfigData.BOT_INTENTS #pulled from config.json

# Various powershell preference settings useful for debugging and decluttering as needed
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
# $VerbosePreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

#Variable Definitions
[int64]$HeartbeatInterval = $null

Register-EngineEvent -SourceIdentifier "WriteChatMessageEvent" -Action { 
    
    function Write-ChatMessage {
        [cmdletbinding()]
        param( $ChannelMessage )
    
        $Timestamp = $ChannelMessage.timestamp
        $Username = $ChannelMessage.author.username
        $UserId = $ChannelMessage.author.id
        $Content = $ChannelMessage.content -Replace "`n", " "
    
        if ((-not [string]::IsNullOrEmpty($ChannelMessage.content)) -Or (-not [string]::IsNullOrWhiteSpace($ChannelMessage.content))) {
            Write-Host -NoNewLine -ForegroundColor Magenta "<$Timestamp - $Username $UserId> "
            Write-Host -NoNewLine -ForegroundColor White "$Content`n"
        }
    }
    
    Write-ChatMessage -ChannelMessage ($Event.SourceArgs)

} | Out-Null


# Generic function to simplify discord websocket calls
function Send-DiscordWebSocketData {
    [cmdletbinding()]
    param( $Data )
    
    $success = $false
    
    try {
        $Message = $Data | ConvertTo-Json
        $Array = @()
        $Message.ToCharArray() | ForEach-Object { $Array += [byte]$_ }
        $Message = New-Object System.ArraySegment[byte]  -ArgumentList @(, $Array)
        $Conn = $WS.SendAsync($Message, [System.Net.WebSockets.WebSocketMessageType]::Text, [System.Boolean]::TrueString, $CT)
        while (!$Conn.IsCompleted) { Start-Sleep -Milliseconds 50 }
        $success = $true
    }
    
    catch {
        Write-Error "Send-DiscordWebSocketData error: $($PSItem.Exception.Message)"
    }
    $msg = if ($success) { "Sent" }else { "SendFailed" }
    return ($Data | Select-Object @{N = "SentOrRecvd"; E = { $msg } }, @{N = "EventName"; E = { $_.t } }, @{N = "SequenceNumber"; E = { $_.s } }, @{N = "Opcode"; E = { $_.op } }, @{N = "Data"; E = { $_.d } })

}

# Discord needs regular heartbeat to keep the websocket connected. Could use simplifying
function Send-DiscordHeartbeat {
    [cmdletbinding()]
    param( [int]$SequenceNumber = $SequenceNumber -is [int] -and $SequenceNumber -eq 0 ? ((Remove-Variable SequenceNumber -ErrorAction SilentlyContinue) && $null) : $SequenceNumber -isnot [int] -and $null -ne $SequenceNumber ? [int]$SequenceNumber : $SequenceNumber )
    
    $Prop = @{ 'op' = 1; 'd' = $SequenceNumber }
    $result = Send-DiscordWebSocketData -Data $Prop
    
    return $result
}

function Send-DiscordResume {
    $Prop = @{ 'op' = 6; 'd' = 0 }
    $result = Send-DiscordWebSocketData -Data $Prop
    
    return $result
}

# More info: https://discord.com/developers/docs/topics/gateway#gateway-intents
function Send-DiscordAuthentication {
    [cmdletbinding()]
    param(
        [string]$Token,
        $Intents
    )
    $IntentsKeys = @{
        'GUILDS'                    = 1 -shl 0
        'GUILD_MEMBERS'             = 1 -shl 1
        'GUILD_BANS'                = 1 -shl 2
        'GUILD_EMOJIS_AND_STICKERS' = 1 -shl 3
        'GUILD_INTEGRATIONS'        = 1 -shl 4
        'GUILD_WEBHOOKS'            = 1 -shl 5
        'GUILD_INVITES'             = 1 -shl 6
        'GUILD_VOICE_STATES'        = 1 -shl 7
        'GUILD_PRESENCES'           = 1 -shl 8
        'GUILD_MESSAGES'            = 1 -shl 9
        'GUILD_MESSAGE_REACTIONS'   = 1 -shl 10
        'GUILD_MESSAGE_TYPING'      = 1 -shl 11
        'DIRECT_MESSAGES'           = 1 -shl 12
        'DIRECT_MESSAGE_REACTIONS'  = 1 -shl 13
        'DIRECT_MESSAGE_TYPING'     = 1 -shl 14
        'MESSAGE_CONTENT'           = 1 -shl 15
        'GUILD_SCHEDULED_EVENTS'    = 1 -shl 16
    }

    foreach ($key in $Intents) {
        # this is being set by looping through and, using a ternary operator like above. Actually reading this again I'm confused.
        $IntentsCalculation = $IntentsCalculation -eq $IntentsKeys[$key] ? $IntentsKeys[$key] : ( $IntentsCalculation + $IntentsKeys[$key] )
    }
    Write-Verbose "Bot Intent Bitmask: $IntentsCalculation"

    $Prop = @{
        'op' = 2;
        'd'  = @{
            'token'      = $Token;
            'intents'    = [int]$IntentsCalculation;
            'properties' = @{
                '$os'      = 'windows';
                '$browser' = 'pwshbot';
                '$device'  = 'pwshbot';
            }
        }
    }

    $result = Send-DiscordWebSocketData -Data $Prop
    return $result
}

$GatewaySession = Invoke-RestMethod -Uri "https://discord.com/api/gateway"
Write-Verbose "$($GatewaySession.url)"

[bool]$mustSendResume = $false
function Invoke-Disconnect {
    param (
        [System.Net.WebSockets.WebSocket]$WebSocket
    )
    if ($WebSocket.CloseStatusDescription -eq "Discord WebSocket requesting client reconnect.") {
        $WebSocket.CloseAsync(([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure), $null, $CT)
    }
}

try {
    do {
        $WS = New-Object System.Net.WebSockets.ClientWebSocket  
        $CT = New-Object System.Threading.CancellationToken
        $Conn = $WS.ConnectAsync($GatewaySession.url, $CT)
        while (!$Conn.IsCompleted) { Start-Sleep -Milliseconds 50 }
        Write-Information "Connected to Web Socket."
        
        while ($WS.State -eq 'Open') {
            
            if ($true -eq $mustSendResume) { #Send Resume on OPCODE 7
                Send-DiscordResume
                $mustSendResume = $false
            }

            #region misc-code
            $DiscordData = ""
            $Size = 512000
            $Array = [byte[]] @(, 0) * $Size
        
            $Recv = New-Object System.ArraySegment[byte] -ArgumentList @(, $Array)
            $Conn = $WS.ReceiveAsync($Recv, $CT) 

            while (!$Conn.IsCompleted) {
                
                Start-Sleep -Milliseconds 50 
            
                # Getting the time between when each heartbeat should be sent
                $CurrentEpochMS = [int64]((New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date)).TotalMilliseconds)
                if ($CurrentEpochMS -ge ($NextHeartbeat)) {
                    Write-Verbose "Sending next heartbeat - $CurrentEpochMS >= $NextHeartbeat."
                    if ($SequenceNumber -ge 1) { Send-DiscordHeartbeat -SequenceNumber $SequenceNumber | Out-Null } 
                    else { Send-DiscordHeartbeat | Out-Null }
                    $NextHeartbeat = (([int64]((New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date)).TotalMilliseconds)) + [int64]$HeartbeatInterval)
                }

            }


            $DiscordData = [System.Text.Encoding]::utf8.GetString($Recv.array)
        
            # $LogStore += $DiscordData 

            try { $RecvObj = $DiscordData | ConvertFrom-Json | Select-Object @{N = "SentOrRecvd"; E = { "Received" } }, @{N = "EventName"; E = { $_.t } }, @{N = "SequenceNumber"; E = { $_.s } }, @{N = "Opcode"; E = { $_.op } }, @{N = "Data"; E = { $_.d } } }
            catch { Write-Error "ConvertFrom-Json failed $_.Exception"; Write-Host "Data: $RecvObj"; $RecvObj = $null; }
        
            # op code meanings are here: https://discord.com/developers/docs/topics/opcodes-and-status-codes#gateway-gateway-opcodes
            
            # this is probably broken but the bot still works so eh
            if ([int]$RecvObj.SequenceNumber -eq 1) { 
                $SequenceNumber = [int]$RecvObj.SequenceNumber 
            }
            elseif ([int]$SequenceNumber -eq 1 -Or [int]$RecvObj.SequenceNumber -gt [int]$SequenceNumber) {  
                $SequenceNumber = [int]$RecvObj.SequenceNumber 
            }

            ## CONVERT TO SWITCH
            switch ($RecvObj.Opcode) {
                0 {
                    if ($RecvObj.Data.resume_gateway_url -notin ($null,"")){
                        Write-Verbose $("Original Gateway URL: {0}" -f ($GatewaySession.url))
                        $GatewaySession.url = ($RecvObj.Data.resume_gateway_url)
                        Write-Verbose $("Resume Gateway URL: {0}" -f ($GatewaySession.url))
                    }
                }
                7 {
                    Write-Verbose "OPCODE 7 Received - Disconnecting and sending Resume OPCODE 6"
                    Invoke-Disconnect
                    $mustSendResume = $true
                }
                9 {
                    Write-Warning "Session invalidated from opcode 9 received. Reauthenticating..."
                    Send-DiscordAuthentication -Token $BotToken -Intents $BotIntents | Out-Null #| Format-Table 
                    Write-Information "Successfully authenticated to Discord Gateway."
                }
                10 {
                    Write-Verbose "HELLO received! Sending first heartbeat."
                    $HeartbeatInterval = [int64]$RecvObj.Data.heartbeat_interval
                    Start-Sleep -Milliseconds ($HeartbeatInterval * 0.1)
                    Send-DiscordHeartbeat | Out-Null
                    Write-Verbose "First heartbeat sent."
                    $HeartbeatStart = [int64]((New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date)).TotalMilliseconds) # epoch time ms
                    $NextHeartbeat = ($HeartbeatStart + [int64]$HeartbeatInterval)
                    $continueAuth = $true
                }
                { $_ -eq 11 -and $continueAuth -eq $true } {
                    $continueAuth = $false
                    Write-Verbose "First ACK received. Attempting authentication."
                    Send-DiscordAuthentication -Token $BotToken -Intents $BotIntents | Out-Null #| Format-Table
                    Write-Information "Successfully authenticated to Discord Gateway."
                }
            }
            ##

            # Call the Script Controller in a new thread to avoid blocking the main-thread which handles WebSocket events.
            # This allows concurrency so multiple users can issue commands to the bot at the same time and prevents the bot from disconnecting on long-running operations.
            try {
                Start-ThreadJob -ArgumentList $syncHash -FilePath .\router.ps1 -ErrorAction SilentlyContinue | Out-Null                
            }
            catch {
                #Ignore the error and drop the event; we were probably modifying the controller file if this happened
            }

            (Get-Job).where({ $_.State -in @("Completed", "Failed") }) | Remove-Job #Cleanup completed jobs

        }
    } until (!$Conn)
}
finally {
    if ($WS) {
        Get-EventSubscriber | Unregister-Event
        Write-Information "Closing websocket"; 
        $WS.CloseAsync(([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure), $null, $CT).GetAwaiter().GetResult() | Out-Null
        $WS.Dispose()
    }
}
