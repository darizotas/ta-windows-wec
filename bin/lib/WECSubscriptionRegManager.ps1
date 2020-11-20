. "$PSScriptRoot\WECUtilHelper.ps1"

<#
.SYNOPSIS
    Removes old/expired event sources from the registry.
.DESCRIPTION
    Removes old/expired event sources from the registry.

    It parses the registry entry HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EventCollector\Subscriptions
    
    And for each subscription it loops through the event sources listed and removes those with a 
    heartbeat time older than the given retention period (days from now).

    It generates a warning if it is unable to remove an event source and stops processing that subscription 
    (with the corresponding error).

    It returns an object with the following members:
    - Subscription
    - Status: Ok, Error
    - ErrorMessage: null or the error message produced by not being able to remove an event source
    - ErrorTime: null or timestamp of the error.
    - EventSource: list of pairs (ComputerName, HeartbeatTime (in UTC)) that have been removed from the registry.

.PARAMETER DaysOld
    Retention period in days. Event sources with a Hearbeat null or older than that are removed. The value must
    be between 59 and 365 days.

.PARAMETER LogFile
    Path to the log file for verbose and error messages

.PARAMETER ReportOnly
    If true, it does not remove the event source from the registry.

.LINK
     https://github.com/MicrosoftDocs/windows-itpro-docs/issues/2599
    https://community.softwaregrp.com/dcvta86296/attachments/dcvta86296/arcsight-discussions/24729/1/Protect2015-WindowsEventForwarding.pdf
#>
function Remove-WECOldEventSourceFromRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateRange(59,365)]
        [int]$DaysOld,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogFile,

        [Parameter()]
        [switch]$ReportOnly
    )

    # Global vars
    $TotalStart = Get-Date
    $Verbose = ($VerbosePreference -eq 'Continue')

    $DateLimit = (Get-Date).AddDays(-$DaysOld)
    $WECRegistryKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EventCollector\Subscriptions"
    Get-ChildItem $WECRegistryKey | ForEach-Object {
        $SubscriptionName = $_.PSChildName
        # Logging
        "Start parsing registry for subscription $SubscriptionName to remove event sources older than $DaysOld days from now" `
            | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose

        # Per subscription vars
        $Start = Get-Date
        $SubscriptionPruneDetails = [PSCustomObject]@{
            Subscription = $SubscriptionName
            Status = "OK"
            ErrorMessage = $null
            ErrorTime = $null
            EventSource = @()
        }
        $Removed = 0
        $Total = 0
        # Start processing event sources
        $EventSource = Get-ChildItem "$WECRegistryKey\$SubscriptionName\EventSources" 
        foreach ($e in $EventSource) {
            $ComputerName = $e.PSChildName
            $LastHeartbeatTimeKey = Get-ItemProperty "$WECRegistryKey\$SubscriptionName\EventSources\$ComputerName" -Name LastHeartbeatTime -ErrorAction Ignore
            $TimeUtc = $null
            if ($LastHeartbeatTimeKey.LastHeartbeatTime) {
                $TimeUtc = ConvertFrom-FileTime -FileTime $LastHeartbeatTimeKey.LastHeartbeatTime
            }
            "Processing Event Source: $ComputerName with LastHearbeatTime (UTC): $TimeUtc" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
            # Prune event source if no heartbeat time or if it is too old
            if (!$TimeUtc -or ($DateLimit -gt $TimeUtc)) {
                try {
                    if (!$ReportOnly) {
                        Remove-Item -Path "$WECRegistryKey\$SubscriptionName\EventSources\$ComputerName" -Force -ErrorAction Stop
                    }

                    "Event Source: $ComputerName removed (Report only: $ReportOnly)" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                    $Removed++  
                    $SubscriptionPruneDetails.EventSource += [PSCustomObject]@{
                        ComputerName = $ComputerName
                        LastHeartBeatTime = $TimeUtc.toString('s')
                    }
                } catch {
                    # Error
                    $SubscriptionPruneDetails.Status = "Error"
                    $SubscriptionPruneDetails.ErrorMessage = $_.Exception.Message
                    $SubscriptionPruneDetails.ErrorTime = (Get-Date).ToString('s')

                    # Logging
                    "Event Source $ComputerName could not be removed" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                    "Processing stopped for Subscription $SubscriptionName. Please check the permissions" | Write-WECUtilLog -Path $LogFile -Level Error -Function $MyInvocation.MyCommand.Name
                    
                    break
                }
            }  
            $Total++
        }
        "Elapsed time: $(New-Timespan $Start $(Get-Date)) ; Event sources processed: $Total, Removed: $Removed" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
        # Return registry prune details
        $SubscriptionPruneDetails
    }
    "Total elapsed time: $(New-Timespan $TotalStart $(Get-Date))" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
}