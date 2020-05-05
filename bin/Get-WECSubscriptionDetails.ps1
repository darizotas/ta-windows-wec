. "$PSScriptRoot\WECSubscriptionParser.ps1"

# https://docs.splunk.com/Documentation/Splunk/8.0.2/SearchReference/Commontimeformatvariables
# https://answers.splunk.com/answers/5357/what-is-the-best-timestamp-format-to-use-for-my-custom-log-to-be-indexed-by-splunk.html

# Read the logging configuration
$Setting = Get-WECUtilSettings
$Verbose = $false
# Check for the section
if ($Setting -and $Setting["logging"]) {
    # Check for the setting and if the value is DEBUG to enable verbose mode.
    if ($Setting["logging"]["log_level"] -and ($Setting["logging"]["log_level"] -ieq "DEBUG")) {
        $Verbose = $true
    }
}

Get-WECSubscriptions | ConvertFrom-WECSubscriptionDetails -Verbose:$Verbose | Foreach-Object {
    $EventLogStats = $_.LogFile | Get-WECEventLogStats -Verbose:$Verbose

    # This only happens on "custom" configuration mode
    $MaxItems = '-'
    if ($_.PSObject.Properties.name -match 'deliverymaxitems') {
        $MaxItems = $_.DeliveryMaxItems
    }

    [PSCustomObject]@{
        Timestamp = [DateTime]::UtcNow.ToString('u')
        Subscription = $_."subscription id"
        Enabled = $_.Enabled
        ConfigurationMode = $_.ConfigurationMode
        DeliveryMode = $_.DeliveryMode
        DeliveryMaxItems = $MaxItems
        DeliveryMaxLatencyTime = $_.DeliveryMaxLatencyTime
        HeartbeatInterval = $_.HeartbeatInterval
        AllowedSourceDomainComputers = $_.AllowedSourceDomainComputers
        EventSource = $_.EventSource
        LogName = $EventLogStats.LogName
        EventPerSecond = $EventLogStats.EventPerSecond
        TotalEvents = $EventLogStats.TotalEvents
        NewestEventTime = $EventLogStats.NewestEventTime.ToString('s')
        OldestEventTime = $EventLogStats.OldestEventTime.ToString('s')
        LogSize = $EventLogStats.LogSize
    } | ConvertTo-Json -Compress  
}