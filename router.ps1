# This script is called asynchronously for every websocket event to allow parallel processing of messages/etc.

using module .\Modules\shared_functions.psm1

[CmdletBinding()]
param (
    $syncHash
)


$RecvObj = $using:RecvObj #REF main thread RecvObj

#Trigger event handler on main-thread to output chat messages to the console. This isn't required for a functional bot.
function Write-ChatMessage {
    param(
        $ChannelMessage
    )

    $syncHash.Host.Runspace.Events.GenerateEvent( "WriteChatMessageEvent", $null, @($ChannelMessage), $null)
}
# Write the chat messages to the terminal
$RecvObj.EventName -eq "MESSAGE_CREATE" ? ( Write-ChatMessage -ChannelMessage $RecvObj.Data ) : $null

#region INIT VOICESTATEINFO
#Initialize the synced dictionary if it doesn't exist
if (!$syncHash.VoiceStateInfo) {
    $syncHash.VoiceStateInfo = New-Object 'System.Collections.Generic.Dictionary[[int64],[int64]]'
}

# Load list of users in voice channels and the channel ID to a synced Dictionary
if ($RecvObj.EventName -eq "GUILD_CREATE") {       
    $RecvObj.Data.voice_states | ForEach-Object {
        $syncHash.VoiceStateInfo[$_.user_id] = $_.channel_id
    }
}
#endregion INIT VOICESTATEINFO

# Simplified name object for channel messages, filters out bots own messages 
# Note - Typical properties for $ChannelMessage: type, tts, timestamp, referenced_message, pinned, nonce, mentions, mention_roles, mention_everyone, id, flags, embeds, edited_timestamp, content, components, channel_id, author, attachments    
$ChannelMessage = if ($RecvObj.EventName -eq "MESSAGE_CREATE") { $RecvObj.Data | Where-Object { $_.author.id -ne $BotId } }

#region Script Router
# There are two ways to do this - a simple switch statement on exact matches or a regex switch which is more flexible but more complex
try {
    #Simple switch for static commands that don't need parameters
    switch ($ChannelMessage.content) {
        "test" { 
            Send-DiscordMessage -Content "Starting sleep for 5 seconds" -ChannelId $ChannelMessage.channel_id
            start-sleep -Seconds 5
            Send-DiscordMessage -Content "Done sleeping" -ChannelId $ChannelMessage.channel_id
        }
        "emoji" { 
            Send-DiscordMessage -Content "<:laugh:691408987811479632>" -ChannelId $ChannelMessage.channel_id
        }
        "time" {
            Send-DiscordMessage -ChannelId $ChannelMessage.channel_id -Content (Get-Date -Format "Server Ti\me: HH:mm:ss")
        }
        "randgif" {
            Send-DiscordMessage -ChannelId $ChannelMessage.channel_id -Content (& .\Scripts\randgif.ps1)
        }
    }

    # More complex REGEX switch for handling parameters
    switch -regex ($ChannelMessage.content) {
        "^google\s.*" {
            $content = & .\Scripts\google.ps1 ($ChannelMessage.content)
            Send-DiscordMessageEmbed `
                -ChannelId $ChannelMessage.channel_id `
                -Content $content `
                -Title "Let me google that for you" `
                -Description $content
        }
        "^stonks.*" { 
            Send-DiscordMessage -ChannelId $ChannelMessage.channel_id -Content (& .\Scripts\stonks.ps1 -OriginalMessage ($ChannelMessage.content))
        }
    }
}
catch {
    Send-DiscordMessage -ChannelId $ChannelMessage.channel_id -Content " @$($ChannelMessage.author.username) - a bot error occurred. Error: $($PSItem.Exception.Message)"
}
finally {
    $Error.Clear()
}
#endregion Script Router



#region GUARD VOICE CHANNEL FUNCTION

#Define Voice Channels for easier programming
$VoiceChannels = @{
    GUARD = 992540164876410921
}

#Define Text Channels for easier programming
$TextChannels = @{
    CLASSIFIED = 683379649706983521
}
function Invoke-VoiceChannelJoinHandler {
    switch ($RecvObj.Data.channel_id) {
        $VoiceChannels.GUARD {
            Send-DiscordMessageEmbed `
                -ChannelId $TextChannels.CLASSIFIED `
                -Content "@everyone CQ CQ CQ - $($RecvObj.Data.member.user.username) CALLING CQ ON GUARD" `
                -Description "$($RecvObj.Data.member.user.username) joined voice channel: GUARD" `
                -Title "OPERATOR IS ON CALLING FREQ - PLEASE RESPOND" `
                -TTS $true
        }
        { $_ -eq $null -and ($syncHash.VoiceStateInfo[$RecvObj.Data.member.user.id] -eq $VoiceChannels.GUARD) } {
            Send-DiscordMessageEmbed -ChannelId $TextChannels.CLASSIFIED -Content "$($RecvObj.Data.member.user.username) left GUARD"
        }
    }
}

if ($RecvObj.EventName -eq "VOICE_STATE_UPDATE") {       
    if ($null -eq $syncHash.VoiceStateInfo[$RecvObj.Data.member.user.id] -or $syncHash.VoiceStateInfo[$RecvObj.Data.member.user.id] -ne $RecvObj.Data.channel_id) {
        Invoke-VoiceChannelJoinHandler
        $syncHash.VoiceStateInfo[$RecvObj.Data.member.user.id] = $RecvObj.Data.channel_id
    }
    $syncHash.VoiceStateInfo[$RecvObj.Data.member.user.id] | write-host
}
#endregion GUARD VOICE CHANNEL FUNCTION