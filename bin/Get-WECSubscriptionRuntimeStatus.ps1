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


Get-WECSubscriptions | ConvertFrom-WECSubscriptionRuntimeStatus -Verbose:$Verbose | Foreach-Object { 
    $_ | Add-Member -MemberType NoteProperty -Name Timestamp -Value ([DateTime]::UtcNow.ToString('u')) -Force -PassThru | `
        ConvertTo-Json -Compress
}