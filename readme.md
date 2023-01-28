# PWSHBOT

## Summary
PWSHBOT is an asynchronous Discord Bot Framework built entirely in PowerShell.

Why PowerShell you may ask? PowerShell is a language that allows you to harness the power of the dotnet framework and rapidly develop impactful scripts. Need to consume a RESTful API? You could write that bot function with a PowerShell "One-Liner using `Invoke-RestMethod`". Need to call functions in an unmanaged DLL to return useful data? PowerShell can do that too; the limit is your imagination.

**This would not have been possible without the fantastic work done by 1-chris**  
https://github.com/1-chris/Powershell-Discord-Bot

## How to use
Rename `config.json.example` to `config.json` and insert your Bot Token, Bot User ID, and Gateway Intents (the possible options have been filled out for you already; just remove what you don't need)

Define your routes in `router.ps1` (what happens on certain message text, etc). Examples are provided in the `router.ps1` file in this repo.

When ready, launch `.\Start-PWSHBot.ps1` with PowerShell 7.0 or higher. In theory, you could run this on top of the official PowerShell docker container to deploy your bot in the cloud.

## How it works
Every WebSocket event received calls `router.ps1` in a new thread to process the event concurrently to avoid blocking the main thread. This is important so we don't miss sending heartbeats to the gateway, gateway migration requests, or delay other users' commands due to a long-running operation.

`router.ps1` shares data with the main thread through the use of a synchronized hashtable, enabling data persistence between events if needed (ex: executing actions on VOICE_STATE events such as when a user joins/leaves a voice-channel) and allowing us to write to the console from our processing thread (`router.ps1`)

Another advantage of this multithreaded approach is that we can update the router script in real-time without restarting the bot.

> **Note:** updating the shared_functions module is not recommended without a bot restart as the module gets loaded by the main thread and processing thread (router) and will result in a module version mismatch causing the bot to misbehave

### Sending messages to Discord
Two cmdlets are included to help send messages to discord.
Sending messages is done via REST API vs websocket so there is no requirement to have a valid session open to send content to a channel - just the bot token and channel ID.
`$BotToken` is set globally in the `shared_functions` module so there is no requirement to specify it when calling the `Send-DiscordMessage` or `Send-DiscordMessageEmbed` cmdlets.

### Router Example
```powershell
...
switch ($ChannelMessage.content) {
        "test" { 
            Send-DiscordMessage `
                -Content "Starting sleep for 5 seconds" `
                -ChannelId $ChannelMessage.channel_id

            Start-Sleep -Seconds 5

            Send-DiscordMessage `
                -Content "Done sleeping" `
                -ChannelId $ChannelMessage.channel_id
        }
}
<#
    Run the bot and send the word "test" in the chat.
    This will send a message, sleep the thread for 5 seconds, then send another message.
    Call this multiple times to witness parallel processing in action.
#>
...
```

## Notes
- This is a work in progress and is not as full-featured or as well-documented as the major frameworks in other languages - although you could probably achieve feature parity if you're creative enough.
- This has only been tested in a single server and is not designed as a large-scale high-performance bot framework that can support thousands of servers at once. Please do not complain if you try and it doesn't work; use NodeJS or C# for that.
- Right now you have to manually specify your Bot's User ID in the config to prevent it from potentially replying to itself - but in the future, I will add code to dynamically query that data on launch and configure itself.
- I have not written unit tests for the framework and quite frankly don't know where to start. If someone wants to contribute and write-unit tests I would be eternally grateful.