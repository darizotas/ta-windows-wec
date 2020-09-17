. "$PSScriptRoot\WECSubscriptionParser.ps1"

# https://docs.splunk.com/Documentation/Splunk/8.0.2/SearchReference/Commontimeformatvariables
# https://answers.splunk.com/answers/5357/what-is-the-best-timestamp-format-to-use-for-my-custom-log-to-be-indexed-by-splunk.html

# Read the logging and paging configuration
$Setting = Get-WECUtilSettings
$RangeSize = 0
$Verbose = $false
# Check for the section
if ($Setting) {
    if ($Setting["logging"]) {
        # Check for the setting and if the value is DEBUG to enable verbose mode.
        if ($Setting["logging"]["log_level"] -and ($Setting["logging"]["log_level"] -ieq "DEBUG")) {
            $Verbose = $true
        }

    }
    # Check for the batch size value
    if ($Setting["eventsource"] -and ($Setting["eventsource"]["rt_splitafter"] -match "^\-?[\d]+$")) {
        # If positive integer, we prepare for splitting the event in batches.
        if ([int]$Setting["eventsource"]["rt_splitafter"] -gt 0) {
            $RangeSize = [int]($Setting["eventsource"]["rt_splitafter"])
        }
    }
}

$Timestamp = [DateTime]::UtcNow.ToString('u')
Get-WECSubscriptions | ConvertFrom-WECSubscriptionRuntimeStatus -Verbose:$Verbose | Foreach-Object { 
    $Event = [PSCustomObject]@{
        Timestamp = $Timestamp
        Subscription = $_.subscription
        RunTimeStatus = $_.runtimestatus
        LastError = $_.lasterror
    }
    # Error properties
    if ($_.PSobject.Properties.Name -contains "errormessage") {
        $Event | Add-Member -MemberType NoteProperty -Name ErrorMessage -Value $_.errormessage -Force -PassThru | Out-Null
    }
    if ($_.PSobject.Properties.Name -contains "errortime") {
        $Event | Add-Member -MemberType NoteProperty -Name ErrorTime -Value $_.errortime -Force -PassThru | Out-Null
    }

    # Split the event according to rt_splitafter
    if ($RangeSize -gt 0) {
        for ($i = 0; $i -lt $_.EventSource.Count; $i+=$RangeSize) {
            $End = $RangeSize + $i - 1
            $Event | Add-Member -MemberType NoteProperty -Name EventSource -Value $_.EventSource[$i..$End] -Force -PassThru | `
                ConvertTo-Json -Compress
        }
    # All in one. Warning! It may break the browser rendering and reach KV JSON char limits   
    } else {
        $Event | Add-Member -MemberType NoteProperty -Name EventSource -Value $_.EventSource -Force -PassThru | `
            ConvertTo-Json -Compress
    }
}