. "$PSScriptRoot\lib\WECSubscriptionRegManager.ps1"

# https://docs.splunk.com/Documentation/Splunk/8.0.2/SearchReference/Commontimeformatvariables
# https://answers.splunk.com/answers/5357/what-is-the-best-timestamp-format-to-use-for-my-custom-log-to-be-indexed-by-splunk.html

# Read the logging and paging configuration
$Setting = Get-WECUtilSettings
$RangeSize = 0
$Verbose = $false
$DaysOld = 60
$ReportOnly = $true
# Check for the section
if ($Setting) {
    if ($Setting["logging"]) {
        # Check for the setting and if the value is DEBUG to enable verbose mode.
        if ($Setting["logging"]["log_level"] -and ($Setting["logging"]["log_level"] -ieq "DEBUG")) {
            $Verbose = $true
        }
    }
    
    # Check for the batch size value
    if ($Setting["eventsource"] -and ($Setting["eventsource"]["pr_splitafter"] -match "^\-?[\d]+$")) {
        # If positive integer, we prepare for splitting the event in batches.
        if ([int]$Setting["eventsource"]["pr_splitafter"] -gt 0) {
            $RangeSize = [int]($Setting["eventsource"]["pr_splitafter"])
        }
    }

    if ($Setting["pruning"]) {
        # Check for days old value
        if ($Setting["pruning"]["days_old"] -match "^\-?[\d]+$") {
            $DaysOld = [int]($Setting["pruning"]["days_old"])
            # It is allowed when between 60 and 365 days.
            if (($DaysOld -lt 60) -or ($DaysOld -gt 365)) {
                $DaysOld = 60
            }
        }
        # Report only?
        if ($Setting["pruning"]["report_only"]) {
            $ReportOnly = [System.Convert]::ToBoolean($Setting["pruning"]["report_only"])
        }
    }
}

# Creates/Rotates the log file
$LogFile = "$SplunkHome\var\log\splunk\splunk_ta-windows-wec-prune-registry.log"
New-WECUtilLogFile -Path $LogFile

$Timestamp = [DateTime]::UtcNow.ToString('u')
Remove-WECOldEventSourceFromRegistry -DaysOld $DaysOld -LogFile $LogFile -ReportOnly:$ReportOnly -Verbose:$Verbose | Foreach-Object { 
    $Event = [PSCustomObject]@{
        Timestamp = $Timestamp
        Subscription = $_.Subscription
        Status = $_.Status
        ErrorMessage = $_.ErrorMessage
        ErrorTime = $_.ErrorTime
    }

    # Split the event according to pr_splitafter
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
