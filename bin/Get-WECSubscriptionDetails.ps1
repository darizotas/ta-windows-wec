. "$PSScriptRoot\lib\WECSubscriptionParser.ps1"

# https://docs.splunk.com/Documentation/Splunk/8.0.2/SearchReference/Commontimeformatvariables
# https://answers.splunk.com/answers/5357/what-is-the-best-timestamp-format-to-use-for-my-custom-log-to-be-indexed-by-splunk.html

# Read the logging configuration
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
    if ($Setting["eventsource"] -and ($Setting["eventsource"]["sd_splitafter"] -match "^\-?[\d]+$")) {
        $RangeSize = [int]($Setting["eventsource"]["sd_splitafter"])
    }
}

# Creates/Rotates the log file
$LogFile = "$SplunkHome\var\log\splunk\splunk_ta-windows-wec-details.log"
New-WECUtilLogFile -Path $LogFile

$Timestamp = [DateTime]::UtcNow.ToString('u')
Get-WECSubscriptions | ConvertFrom-WECSubscriptionDetails -LogFile $LogFile -Verbose:$Verbose | Foreach-Object {
    $EventLogStats = $_.LogFile | Get-WECEventLogStats -LogFile $LogFile -Verbose:$Verbose

    # This only happens on "custom" configuration mode
    $MaxItems = '-'
    if ($_.PSObject.Properties.name -contains 'deliverymaxitems') {
        $MaxItems = $_.DeliveryMaxItems
    }

    $Event = [PSCustomObject]@{
        Timestamp = $Timestamp
        Subscription = $_."subscription id"
        Enabled = $_.Enabled
        ConfigurationMode = $_.ConfigurationMode
        DeliveryMode = $_.DeliveryMode
        DeliveryMaxItems = $MaxItems
        DeliveryMaxLatencyTime = $_.DeliveryMaxLatencyTime
        HeartbeatInterval = $_.HeartbeatInterval
        AllowedSourceDomainComputers = $_.AllowedSourceDomainComputers
        LogName = $EventLogStats.LogName
        EventPerSecond = $EventLogStats.EventPerSecond
        TotalEvents = $EventLogStats.TotalEvents
        NewestEventTime = $EventLogStats.NewestEventTime.ToString('s')
        OldestEventTime = $EventLogStats.OldestEventTime.ToString('s')
        LogSize = $EventLogStats.LogSize
    } 
    
    # No event sources to add
    if ($RangeSize -lt 0) {
        $Event | ConvertTo-Json -Compress
    # All in one. Warning! It may break the browser rendering and reach KV JSON char limits   
    } elseif ($RangeSize -eq 0) {
        $Event | Add-Member -MemberType NoteProperty -Name EventSource -Value $_.EventSource -Force -PassThru | `
            ConvertTo-Json -Compress
    # Split the event according to sd_splitafter
    } else {
        for ($i = 0; $i -lt $_.EventSource.Count; $i+=$RangeSize) {
            $End = $RangeSize + $i - 1
            $Event | Add-Member -MemberType NoteProperty -Name EventSource -Value $_.EventSource[$i..$End] -Force -PassThru | `
                ConvertTo-Json -Compress
        }
    }
}