$CONFIG = @{
    GIPHY_APIKEY = "PUT API KEY HERE"
    RATING       = "r"
}

$CONFIG.GIPHY_APIKEY.Length -ne 32 ? (return "You need to put a Giphy API key into randgif.ps1") : $null

try { (Invoke-RestMethod "https://api.giphy.com/v1/gifs/random?apikey=$($CONFIG.GIPHY_APIKEY)s&rating=$($CONFIG.RATING)").data.embed_url }
catch { "ERROR GETTING RANDOM GIF" }