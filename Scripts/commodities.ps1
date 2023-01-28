$APIKEY = "PUT API KEY HERE"


$APIKEY -eq "PUT API KEY HERE" ? (return "Please obtain an alphavantage API key for free and put it in commodities.ps1") : $null #You can remove this when you put an API key in

$ENDPOINTS = @{
    NATGAS = "https://www.alphavantage.co/query?function=NATURAL_GAS&interval=monthly&apikey=$($APIKEY)"
    COFFEE = "https://www.alphavantage.co/query?function=COFFEE&interval=monthly&apikey=$($APIKEY)"
    SUGAR  = "https://www.alphavantage.co/query?function=SUGAR&interval=monthly&apikey=$($APIKEY)"
    REALGDP  = "https://www.alphavantage.co/query?function=REAL_GDP&interval=monthly&apikey=$($APIKEY)"
}


$ENDPOINTS.Keys | ForEach-Object {
    $res = Invoke-RestMethod $ENDPOINTS[$_]
    "{0}: {1} {2}" -f ($res.name),($res.data | Select-Object -first 1).Value,($res.unit)
    Start-Sleep -Milliseconds 200
} | Out-String