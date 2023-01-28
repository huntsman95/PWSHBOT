$Global:BotConfigData = Get-Content "$($PSScriptRoot)\..\config.json" | ConvertFrom-Json

$Global:BotToken = $BotConfigData.BOT_TOKEN #See: https://discord.com/developers/applications
$Global:BotId = $BotConfigData.BOT_ID #Set this so the bot doesn't respond to itself. #TODO: Grab bot ID from API and set this variable on connect.


$Headers = @{
    "Authorization" = "Bot $BotToken"
    "User-Agent"    = "DiscordBot (https://github.com/huntsman95/PWSHBot, v1.0.0)"
}
function Send-DiscordMessage {
    [cmdletbinding()]
    param(
        $Token = $BotToken,
        $ChannelId,
        [string]$Content
    )

    $Body = @{
        "content" = "$Content"
    }
    # this uses rest api instead of gateway to create new messages
    # more info: https://discord.com/developers/docs/resources/channel#create-message
    Invoke-RestMethod -Method POST -Uri "https://discord.com/api/v9/channels/$ChannelId/messages" -Headers $Headers -Body $Body | Out-Null # out-null at the end here just means discard whatever is being returned
}

function Send-DiscordMessageEmbed {
    [cmdletbinding()]
    param(
        $Token = $BotToken,
        [string]$ChannelId,
        [string]$Content,
        [string]$Title,
        [string]$Description,
        [bool]$TTS = $false
    )

    if($null -eq $Description -or "" -eq $Description){
        $Description = $Content
    }

    $Body = @{
        "content" = "$Content"
        "tts" = $TTS
        "embeds" = @(@{
            "title" = "$Title"
            "description" = "$Description"
            "color"= 0x00FFAF
        })
    } | ConvertTo-Json
    # this uses rest api instead of gateway to create new messages
    # more info: https://discord.com/developers/docs/resources/channel#create-message
    Invoke-RestMethod -Method POST -Uri "https://discord.com/api/v9/channels/$ChannelId/messages" -Headers $Headers -Body $Body -ContentType "application/json" | Out-Null # out-null at the end here just means discard whatever is being returned
}



