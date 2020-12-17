. "$PSScriptRoot\WECUtilHelper.ps1"

<#
.SYNOPSIS
    This class contains all the properties that belong to the runtime status of an event source.
.DESCRIPTION
    This class contains all the properties that belong to the runtime status of an event source.

    - ComputerName : event source computer name.
    - RunTimeStatus : runtime status.
    - LastError: last error value.
    - LastHeartbeatTime : Time stamp with the last check-in.
.LINK
     https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/wecutil
#>
class EventSourceRuntimeStatus {
    [string]$ComputerName
    [string]$RunTimeStatus
    [string]$LastError
    [string]$LastHeartbeatTime

    EventSourceRuntimeStatus($ComputerName) {
        $this.ComputerName = $ComputerName
    }

    [bool]IsComplete() {
        return $this.ComputerName -and $this.RunTimeStatus -and $this.LastError #-and $this.LastHeartbeatTime
    }
    
    [string]ToString() {
        return "Computer: " + $this.ComputerName + ", Runtime Status: " + $this.RunTimeStatus + `
            ", LastError: " + $this.LastError + ", Heartbeat: " + $this.LastHeartbeatTime
    }
}

<#
.SYNOPSIS
    This class contains all the properties that belong to the event source in the subscription details.
.DESCRIPTION
    This class contains all the properties that belong to the event source in the subscription details.
    This event source only appears when invoking "wecutil gs SUBSCRIPTION_NAME", if the format is changed
    to XML, then this element does not appear.

    - Address : event source computer name.
    - Enabled : status.
.LINK
     https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/wecutil
#>
class EventSource {
    [string]$Address
    [string]$Enabled

    [bool]IsComplete() {
        return $this.Address -and $this.Enabled
    }
    
    [string]ToString() {
        return "Address: " + $this.Address + ", Enabled: " + $this.Enabled
    }
}

<#
.SYNOPSIS
    Converts "wecutil gr SUBSCRIPTION_NAME" command into an object.
.DESCRIPTION
    Converts "wecutil gr SUBSCRIPTION_NAME" command into an object.

    It generates warnings in case there's a missing property or a property gets overwritten. It also warns
    about the skipped lines and event sources that are "malformed", that is, a property is missing.

    File format should be:

    Subscription: SUBSCRIPTION_NAME
	RunTimeStatus: Active
	LastError: 0
	EventSources:
		HOSTNAME_FQDN
			RunTimeStatus: Active
			LastError: 0
			LastHeartbeatTime: 2020-03-06T13:43:13.457
        ...

.PARAMETER Subscription
    List of subscription names to convert

.PARAMETER LogFile
    Path to the log file for verbose and error messages

.EXAMPLE 
    ConvertFrom-WECSubscriptionRuntimeStatus -Subscription SUBSCRIPTION_NAME -Verbose

    VERBOSE: Start parsing runtime status for subscription SUBSCRIPTION_NAME
    VERBOSE: Parsing property subscription : SUBSCRIPTION_NAME
    VERBOSE: Parsing property runtimestatus : Active
    VERBOSE: Parsing property lasterror : 0
    VERBOSE: Start property eventsources
    VERBOSE: Start parsing Event Source: hostname.your.domain.com
    VERBOSE: Parsing Event Source property runtimestatus : Active
    VERBOSE: Parsing Event Source property lasterror : 0
    VERBOSE: Parsing Event Source property lastheartbeattime : 2020-03-06T13:43:13.457
    VERBOSE: Event Source added    
    ...
    VERBOSE: Elapsed time: 00:00:00.3439851
    VERBOSE: Total elapsed time: 00:00:00.3489868

.EXAMPLE 
    @(SUBSRIPTION_1, SUBSCRIPTION_2) | ConvertFrom-WECSubscriptionRuntimeStatus -Verbose

.EXAMPLE 
    @(SUBSRIPTION_1, SUBSCRIPTION_2) | ConvertFrom-WECSubscriptionRuntimeStatus -LogFile "PATH\TO\LOGFILE" -Verbose

.LINK
     https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/wecutil
    EventSourceRuntimeStatus
#>
function ConvertFrom-WECSubscriptionRuntimeStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Subscription,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogFile
    )

    BEGIN {
        $TotalStart = Get-Date
        $Verbose = ($VerbosePreference -eq 'Continue')
    }

    PROCESS {
        foreach ($s in $Subscription) {
            # Counters initialisation
            $Start = Get-Date
            $SkippedLine = 0
            $SkippedEventSource = 0
            # Runtime status data initialisation
            $RuntimeStatus = [PSCustomObject]@{
                EventSource = @()
            }
            $IsSubscriptionProperty = $true
            $EventSource = $null
            
            "Start parsing runtime status for subscription $s" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
            & wecutil gr $s | ForEach-Object {
                if ($_ -match '^\s*([\w\.\-]+)\s*:?\s*(.*)\s*$') {
                    $Key = $($Matches.1).ToLower()
                    $Value = $($Matches.2).Trim()
                    # Subscription runtime status.
                    if ($IsSubscriptionProperty) {
                        if ($Key -eq "eventsources") {
                             $IsSubscriptionProperty = $false
                             "Start property $key" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                             # Subscription runtime status: "subscription", "runtimestatus", "lasterror"
                        } else {
                            "Parsing property $Key : $Value" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                            if ($RuntimeStatus.PSObject.Properties.name -match $Key) {
                                "Subscription property '$Key' overwritten!" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                            }
                            $RuntimeStatus | Add-Member -MemberType NoteProperty -Name $Key -Value $Value -PassThru -Force | Out-Null
                        }
                    # Event source runtime status
                    } else {
                        # Event source runtime status: "runtimestatus", "lasterror", "lastheartbeattime"
                        if ($Value) {
                            "Parsing Event Source property $Key : $Value" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                            if ($EventSource.$Key) {
                                "Event source property '$Key' overwritten!" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                            }
                            $EventSource.$Key = $Value
                        # Computer name only
                        } else {
                            # Event source parsed
                            if ($EventSource) {
                                if ($EventSource.IsComplete()) {
                                    "Event Source added" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                                    $RuntimeStatus.EventSource += $EventSource
                                } else {
                                    "Skipping Event Source $EventSource" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                                    $SkippedEventSource++
                                }
                                $EventSource = $null
                            }

                            "Start parsing Event Source: $Key" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                            [EventSourceRuntimeStatus]$EventSource = [EventSourceRuntimeStatus]::new($Key)
                        }
                    }
                # Let's warn about non empty lines...
                } elseif ($_) {
                    "Skipped line: $_"| Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                    $SkippedLine++
                }
            }
            # Last lingering event source?
            if ($EventSource) {
                if ($EventSource.IsComplete()) {
                    "Event Source added" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                    $RuntimeStatus.EventSource += $EventSource
                } else {
                    "Skipping Event Source $($EventSource | out-string)" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                    $SkippedEventSource++
                }
                $EventSource = $null
            }
            # Warnings
            if ($SkippedEventSource) {
                "$SkippedEventSource malformed and skipped event sources! Please re-run the script in Verbose mode!" | `
                    Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
            }
            if ($SkippedLine) {
                "$SkippedLine skipped lines! Please re-run the script in Verbose mode!" | `
                    Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
            }

            "Elapsed time: $(New-Timespan $Start $(Get-Date))" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose

            # Return runtime status
            $RuntimeStatus
        }

    }

    END {
        "Total elapsed time: $(New-Timespan $TotalStart $(Get-Date))" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
    }
}

# function ConvertFrom-WECSubscriptionDetailsXml {
#     [CmdletBinding()]
#     param(
#         [Parameter(Mandatory=$true)]
#         [ValidateNotNullOrEmpty()]
#         [string]$Subscription
#     )
    
#     $problem = $false
#     "Start parsing details for subscription $Subscription" | Write-WECUtilLog -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
#     try { 
#         #[xml]$Details = & wecutil gs $Subscription /f:XML
#         [xml]$Details = Get-Content ".\wecutil-gs-w10applocker.xml"
#     } catch { 
#         $problem = $true 
#         "An error occured while attempting to parse subscritpion details" | Write-WECUtilLog -Level Warn -Function $MyInvocation.MyCommand.Name 
#     } 

#     if (!$problem) {
#         $Sddl = ConvertFrom-SddlString -Sddl $Details.Subscription.AllowedSourceDomainComputers
#         return [PSCustomObject]@{
#             SubscriptionId = $Details.Subscription.SubscriptionId
#             Enabled = $Details.Subscription.Enabled
#             LogFile = $Details.Subscription.LogFile
#             AllowedSourceDomainComputers = [PSCustomObject]@{
#                 "SDDL" = $Details.Subscription.AllowedSourceDomainComputers
#                 "DACL" = ($Sddl.DiscretionaryACL | Out-String)
#                 "SACL" = ($Sddl.SystemAcl | Out-String)
#             }
#         }
#     } else {
#         return $null
#     }
# }

<#
.SYNOPSIS
    Converts "wecutil gs SUBSCRIPTION_NAME" command output into a PowerShell object.
.DESCRIPTION
    Converts "wecutil gs SUBSCRIPTION_NAME" command output into a PowerShell object.

    It generates warnings in case there's a property gets overwritten. It also warns
    about the skipped lines and event sources that are "malformed", that is, a property is missing.

    File format should be:

    Subscription Id: SUBSCRIPTION_NAME
    SubscriptionType: SourceInitiated
    Description: Subscription events
    Enabled: true
    Uri: http://schemas.microsoft.com/wbem/wsman/1/windows/EventLog
    ConfigurationMode: MinLatency
    DeliveryMode: Push
    DeliveryMaxLatencyTime: 30000
    HeartbeatInterval: 3600000
    Query: 
    <QueryList>
        <Query Id="0" Path="System">
            <!-- https://github.com/nsacyber/Event-Forwarding-Guidance/tree/master/Events#system-or-service-failures -->
            <Select Path="System">*[System[(EventID=7022 or EventID=7023 or EventID=7024 or EventID=7026 or EventID=7031 or EventID=7032 or EventID=7034)]]</Select>
        </Query>
    </QueryList>

    ReadExistingEvents: true
    TransportName: http
    ContentFormat: Events
    Locale: fr-BE
    LogFile: ForwardedEvents
    AllowedIssuerCAList:
    AllowedSubjectList:
    DeniedSubjectList:
    AllowedSourceDomainComputers: O:NSG:BAD:P(A;;GA;;;DC)(A;;GA;;;DC)S:

    EventSource[0]:
        Address: 02di20182012345.my.domain.local
        Enabled: true
    EventSource[1]:
        Address: 02DI20182012345.my.domain.local
        Enabled: true
        ...

.PARAMETER Subscription
    List of subscription names to convert

.PARAMETER LogFile
    Path to the log file for verbose and error messages

.EXAMPLE 
    ConvertFrom-WECSubscriptionDetails -Subscription SUBSCRIPTION_NAME -Verbose

    VERBOSE: Parsing Subscription property subscription id : W10-Applocker
    VERBOSE: Parsing Subscription property subscription id : W10-Applocker 2
    WARNING: Subscription property subscription id overwritten!
    VERBOSE: Parsing Subscription property subscriptiontype : SourceInitiated
    VERBOSE: Parsing Subscription property description : Applocker events
    VERBOSE: Parsing Subscription property enabled : true
    VERBOSE: Parsing Subscription property uri : http://schemas.microsoft.com/wbem/wsman/1/windows/EventLog
    VERBOSE: Parsing Subscription property configurationmode : MinLatency
    VERBOSE: Parsing Subscription property deliverymode : Push
    VERBOSE: Parsing Subscription property deliverymaxlatencytime : 30000
    VERBOSE: Parsing Subscription property heartbeatinterval : 3600000
    VERBOSE: Start property query
    VERBOSE: Query property parsed: <QueryList>  <Query Id="0" Path="System">    <!-- https://github.com/nsacyber/Event-Forwarding-Guidance/tree/master/Events#system-or-service-failures -->
            <Select Path="System">*[System[(EventID=7022 or EventID=7023 or EventID=7024 or EventID=7026 or EventID=7031 or EventID=7032 or EventID=7034)]]</Select>    </Query>    </QueryList>
    VERBOSE: Parsing Subscription property readexistingevents : true
    VERBOSE: Parsing Subscription property transportname : http
    VERBOSE: Parsing Subscription property contentformat : Events
    VERBOSE: Parsing Subscription property locale : fr-BE
    VERBOSE: Parsing Subscription property logfile : ForwardedEvents
    VERBOSE: Parsing Subscription property allowedissuercalist :
    VERBOSE: Parsing Subscription property allowedsubjectlist :
    VERBOSE: Parsing Subscription property deniedsubjectlist :
    VERBOSE: Parsing Subscription property allowedsourcedomaincomputers :
    O:NSG:BAD:P(A;;GA;;;DC)(A;;GA;;;DC)S:
    VERBOSE: Start property eventsource[0]
    VERBOSE: Parsing Event Source property address : 02di20182012345.my.domain.local
    VERBOSE: Parsing Event Source property enabled : true
    VERBOSE: Event Source added  
    VERBOSE: Start property eventsource[1]
    ...
    VERBOSE: Elapsed time: 00:00:00.3439851
    VERBOSE: Total elapsed time: 00:00:00.3489868

.EXAMPLE 
    @(SUBSRIPTION_1, SUBSCRIPTION_2) | ConvertFrom-WECSubscriptionDetails -Verbose

.EXAMPLE 
    @(SUBSRIPTION_1, SUBSCRIPTION_2) | ConvertFrom-WECSubscriptionDetails -LogFile "PATH\TO\LOGFILE" -Verbose

.LINK
     https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/wecutil
    https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-sddlstring
    EventSource
#>
function ConvertFrom-WECSubscriptionDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Subscription,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogFile
    )

    BEGIN {
        $TotalStart = Get-Date
        $Verbose = ($VerbosePreference -eq 'Continue')
    }

    PROCESS {
        foreach ($s in $Subscription) {
            $Start = Get-Date

            $SubscriptionDetails = [PSCustomObject]@{
                EventSource = @()
            }
            $SkippedLine = 0
            $SkippedEventSource = 0
            # Query property flag and buffer
            $IsQueryDetails = $false
            $QueryList = ""
            # EventSource property flag and object
            $IsEventSourceDetails = $false
            $EventSource = $null

            "Start parsing details for subscription $s" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
            & wecutil gs $s | ForEach-Object {
                if ($_ -match '^\s*(\w+\s*(?:\w+|\[\d+\]))\s*:(.*)$') {
                    $Key = $($Matches.1).ToLower()
                    $Value = $($Matches.2).Trim()
                    
                    # Translate SDDL
                    if ($Key -eq "allowedsourcedomaincomputers") {
                        "Parsing Subscription property $Key : $Value" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                        try {
                            $Sddl = ConvertFrom-SddlString -Sddl $Value
                        
                            $AllowedComputers = [PSCustomObject]@{
                                SDDL = $Value
                                DACL = ($Sddl.DiscretionaryACL | Out-String)
                                SACL = ($Sddl.SystemAcl | Out-String)
                            }
                        } catch {
                            "$_" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                            $AllowedComputers = [PSCustomObject]@{
                                SDDL = $Value
                                DACL = ""
                                SACL = ""
                            }
                        }

                        if ($SubscriptionDetails.PSObject.Properties.name -match $Key) {
                            "Subscription property '$Key' overwritten!" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                        }
                        $SubscriptionDetails | Add-Member -MemberType NoteProperty -Name $Key -Value $AllowedComputers -PassThru -Force | Out-Null
                    # Query property starts!
                    } elseif ($Key -eq "query") {
                        "Start property $Key" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                        $IsQueryDetails = $true
                    # Event source starts!
                    } elseif ($Key.StartsWith("eventsource")) {
                        if ($EventSource) {
                            if ($EventSource.IsComplete()) {
                                "Event Source added" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                                $SubscriptionDetails.EventSource += $EventSource
                            } else {
                                "Skipping Event Source $EventSource" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                                $SkippedEventSource++
                            }
                            $EventSource = $null
                        }
                        "Start property $Key" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                        $IsEventSourceDetails = $true
                        [EventSource]$EventSource = [EventSource]::new()
                    # Event source parsing
                    } elseif ($IsEventSourceDetails) {
                        "Parsing Event Source property $Key : $Value" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                        if ($EventSource.$Key) {
                            "Event source property $Key overwritten!" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                        }
                        $EventSource.$Key = $Value
                    # Subscription property
                    } else {
                        "Parsing Subscription property $Key : $Value" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                        if ($SubscriptionDetails.PSObject.Properties.name -match $Key) {
                            "Subscription property '$Key' overwritten!" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                        }
                        $SubscriptionDetails | Add-Member -MemberType NoteProperty -Name $Key -Value $Value -PassThru -Force | Out-Null
                    }
                # Query property parsing
                } elseif ($IsQueryDetails) {
                    $QueryList += $_
                    # Finished parsing Query property
                    if ($_ -ilike "*</QueryList>*") {
                        "Query property parsed: $QueryList" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                        if ($SubscriptionDetails.PSObject.Properties.name -match "query") {
                            "Subscription property 'query' overwritten!" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                        }
                        $SubscriptionDetails | Add-Member -MemberType NoteProperty -Name "query" -Value $QueryList -PassThru -Force | Out-Null
                        $IsQueryDetails = $false
                        $QueryList = ""
                    }
                # Let's warn about non empty lines...
                } elseif ($_) {
                    "Skipped line: $_" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                    $SkippedLine++
                }
            }

            if ($EventSource) {
                if ($EventSource.IsComplete()) {
                    "Event Source added" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
                    $SubscriptionDetails.EventSource += $EventSource
                } else {
                    "Skipping Event Source $EventSource" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
                    $SkippedEventSource++
                }
                $EventSource = $null
            }

            # Warnings
            if ($SkippedEventSource) {
                "$SkippedEventSource malformed and skipped event sources! Please re-run the script in Verbose mode!" | `
                    Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
            }
            if ($SkippedLine) {
                "$SkippedLine skipped lines! Please re-run the script in Verbose mode!" | `
                    Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
            }
            "Elapsed time: $(New-Timespan $Start $(Get-Date))" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose

            # Return subscription details
            $SubscriptionDetails
        }
    }

    END {
        "Total elapsed time: $(New-Timespan $TotalStart $(Get-Date))" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose
    }
}

<#
.SYNOPSIS
    Returns the subscriptions contained in the WEC server.
.DESCRIPTION
    Returns the subscriptions contained in the WEC server.

    It is a wrapper of the command "wecutil es"

.EXAMPLE 
    Get-WECSubscriptions

.LINK
     https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/wecutil
#>
function Get-WECSubscriptions {
    & wecutil es | ForEach-Object {
        [PSCustomObject]@{
            Subscription = $_
        }
    }
}

<#
.SYNOPSIS
    Given a LogName calculates some EPS statistics.
.DESCRIPTION
    Given a LogName calculates some EPS statistics.

    It returns an object with the following properties:
    - LogName : log name.
    - EventPerSecond : Number of events per seconds (EPS).
    - TotalEvents: Total number of events.
    - NewestEventTime : Time stamp of the newest event in the log.
    - OldestEventTime : Time stamp of the oldest event in the log.
    - LogSize : Log size in Bytes.

    The idea has been taken from QRadar github repo.

.PARAMETER LogName
    List of EventLog names.

.PARAMETER LogFile
    Path to the log file for verbose and error messages

.EXAMPLE 
    @("Application", "System") | Get-WECEventLogStats

.EXAMPLE 
    @("Application", "System") | Get-WECEventLogStats -LogFile "PATH\TO\LOGFILE"

.LINK
    https://www.ibm.com/support/pages/qradar-how-measure-eps-rate-microsoft-windows-host
    https://github.com/ibm-security-intelligence/wincollect/tree/master/EventLogReport
#>
function Get-WECEventLogStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$LogName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogFile
    )

    BEGIN {
        $TotalStart = Get-Date
        $Verbose = ($VerbosePreference -eq 'Continue')
    }

    PROCESS {
        foreach ($ln in $LogName) {
            # Oldest event time
            $OldestEvent = Get-WinEvent $ln -Oldest -maxevents 1 -ErrorAction Ignore
            if ($OldestEvent) {
                $OldestEventTime = $OldestEvent.TimeCreated
            } else {
                $OldestEventTime = Get-Date -Date "01/01/1970"
                "No events were found in $ln. Oldest event time set to 01-01-1970" | `
                    Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
            }
            # Newest event time
            $NewestEvent = Get-WinEvent $ln -maxevents 1 -ErrorAction Ignore
            if ($NewestEvent) {
                $NewestEventTime = $NewestEvent.TimeCreated
            } else {
                $NewestEventTime = Get-Date -Date "01/01/1970"
                "No events were found in $ln. Newest event time set to 01-01-1970" | `
                    Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
            }
            # EventLog size and total num of events
            $EventLog = Get-WinEvent -ListLog $ln -ErrorAction Ignore
            if ($EventLog) {
                $TotalLogEvents = $EventLog.RecordCount
                $LogSize = $EventLog.FileSize
            } else {
                $TotalLogEvents = 0
                $LogSize = 0
                "EventLog $ln does not exist" | Write-WECUtilLog -Path $LogFile -Level Warn -Function $MyInvocation.MyCommand.Name
            }
            # Events per second
            $TotalTime = (Get-Date).Subtract($OldestEventTime).TotalSeconds
            $AvgEventsPerSecond = [math]::Round(($TotalLogEvents / $TotalTime), 5)         

            return [PSCustomObject]@{
                LogName = $ln
                EventPerSecond = $AvgEventsPerSecond
                TotalEvents = $TotalLogEvents
                NewestEventTime = $NewestEventTime
                OldestEventTime = $OldestEventTime
                LogSize = $LogSize
            }
        }
    }

    END {
        "Total elapsed time: $(New-Timespan $TotalStart $(Get-Date))" | Write-WECUtilLog -Path $LogFile -Function $MyInvocation.MyCommand.Name -Verbose:$Verbose 
    }
}