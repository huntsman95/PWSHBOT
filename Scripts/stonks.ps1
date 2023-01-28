<#
.SYNOPSIS
    Webscraping example for Discord Bot
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $OriginalMessage
)

$ticker = try {
    ($OriginalMessage | Select-String -Pattern "stonks\s(\w+)").Matches.Groups[1].Value
}
catch {
    $null
}


$webSession = $null

$data = "country%5B%5D=5&sector=36%2C25%2C27%2C28%2C24%2C29%2C35%2C30%2C26%2C34%2C33%2C31%2C32&industry=182%2C190%2C204%2C199%2C212%2C177%2C172%2C207%2C214%2C217%2C179%2C184%2C203%2C181%2C185%2C197%2C222%2C215%2C220%2C202%2C200%2C187%2C229%2C209%2C210%2C192%2C195%2C193%2C228%2C206%2C218%2C205%2C208%2C194%2C183%2C196%2C178%2C230%2C225%2C223%2C216%2C173%2C174%2C180%2C188%2C201%2C211%2C232%2C186%2C226%2C175%2C227%2C231%2C213%2C219%2C198%2C221%2C191%2C189%2C176%2C224&equityType=ORD%2CDRC%2CPreferred%2CUnit%2CClosedEnd%2CREIT%2CELKS%2COpenEnd%2CRight%2CParticipationShare%2CCapitalSecurity%2CPerpetualCapitalSecurity%2CGuaranteeCertificate%2CIGC%2CWarrant%2CSeniorNote%2CDebenture%2CETF%2CADR%2CETC&exchange%5B%5D=2&exchange%5B%5D=1&exchange%5B%5D=50&exchange%5B%5D=95&pn=1&order%5Bcol%5D=eq_market_cap&order%5Bdir%5D=d"

Invoke-WebRequest "https://www.investing.com/stock-screener/?sp=country::5%7Csector::a%7Cindustry::a%7CequityType::a%7Cexchange::a%3Ceq_market_cap;1" -Method GET -WebSession $webSession | Out-Null

$Headers = @{
    "accept"           = "application/json"
    "origin"           = "https://www.investing.com"
    "referer"          = "https://www.investing.com/stock-screener/?sp=country::5|sector::a|industry::a|equityType::a%3Ceq_market_cap;1"
    "x-requested-with" = "XMLHttpRequest"
}

$res = Invoke-RestMethod "https://www.investing.com/stock-screener/Service/SearchStocks" -Headers $Headers -Method POST -Body $data -WebSession $webSession

$decoded = $res | ConvertFrom-Json -AsHashtable

$InterestingTickers = $null

<#
    This is the part where we filter our data
#>

$InterestingTickers = @(
    "AAPL"
    , "GOOG"
    , "MSFT"
    , "AMZN"
    , "TCTZF"
    , "NVDA"
    , "WMT"
    , "SSNLF"
    , "META"
    , "JPM"
)
switch ($ticker) {
    $null {
        $hits = $decoded.hits.where({ $_.stock_symbol -in $InterestingTickers })
    }
    Default {
        $hits = $decoded.hits.where({ $_.stock_symbol -eq $ticker })
    }
}

if($null -eq $hits){
    return "No stock matching that ticker was found"
}


$hitsTable = $hits | Select-Object `
@{n = "Name"; e = "name_trans" } `
    , @{n = "Sector"; e = "sector_trans" } `
    , @{n = "Exchange"; e = "exchange_trans" } `
    , @{n = "Symbol"; e = "stock_symbol" } `
    , @{n = "Last"; e = "last" } `
    , @{n = "Change %"; e = "daily" } `
    , @{n = "Vol"; e = "turnover_volume_frmt" } `
| Format-Table `
| Out-String

return @"
``````
$hitsTable
``````
"@