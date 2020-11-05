Function Get-IniContent {  
    <#  
    .Synopsis  
        Gets the content of an INI file  
          
    .Description  
        Gets the content of an INI file and returns it as a hashtable  
          
    .Notes  
        Author        : Oliver Lipkau <oliver@lipkau.net>  
        Blog        : http://oliver.lipkau.net/blog/  
        Source        : https://github.com/lipkau/PsIni 
                      http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91 
        Version        : 1.0 - 2010/03/12 - Initial release  
                      1.1 - 2014/12/11 - Typo (Thx SLDR) 
                                         Typo (Thx Dave Stiff) 
          
        #Requires -Version 2.0  
          
    .Inputs  
        System.String  
          
    .Outputs  
        System.Collections.Hashtable  
          
    .Parameter FilePath  
        Specifies the path to the input file.  
          
    .Example  
        $FileContent = Get-IniContent "C:\myinifile.ini"  
        -----------  
        Description  
        Saves the content of the c:\myinifile.ini in a hashtable called $FileContent  
      
    .Example  
        $inifilepath | $FileContent = Get-IniContent  
        -----------  
        Description  
        Gets the content of the ini file passed through the pipe into a hashtable called $FileContent  
      
    .Example  
        C:\PS>$FileContent = Get-IniContent "c:\settings.ini"  
        C:\PS>$FileContent["Section"]["Key"]  
        -----------  
        Description  
        Returns the key "Key" of the section "Section" from the C:\settings.ini file  
          
    .Link  
        Out-IniFile  
    #>  
      
    [CmdletBinding()]  
    Param(  
        [ValidateNotNullOrEmpty()]  
        [ValidateScript({Test-Path $_})]  
        [Parameter(ValueFromPipeline=$True,Mandatory=$True)]  
        [string]$FilePath  
    )  
      
    Begin  
        {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"}  
          
    Process  
    {  
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing file: $Filepath"  
              
        $ini = @{}  
        switch -regex -file $FilePath  
        {  
            "^\[(.+)\]$" # Section  
            {  
                $section = $matches[1]  
                $ini[$section] = @{}  
                $CommentCount = 0  
            }  
            "^(;.*)$" # Comment  
            {  
                if (!($section))  
                {  
                    $section = "No-Section"  
                    $ini[$section] = @{}  
                }  
                $value = $matches[1]  
                $CommentCount = $CommentCount + 1  
                $name = "Comment" + $CommentCount  
                $ini[$section][$name] = $value  
            }   
            "(.+?)\s*=\s*(.*)" # Key  
            {  
                if (!($section))  
                {  
                    $section = "No-Section"  
                    $ini[$section] = @{}  
                }  
                $name,$value = $matches[1..2]  
                $ini[$section][$name] = $value  
            }  
        }  
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Processing file: $FilePath"  
        Return $ini  
    }  
          
    End  
        {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended"}  
} 

<#
.SYNOPSIS
    Gets the TA-WECUtil configuration from file.
.DESCRIPTION
    Gets the TA-WECUtil configuration from file.

    It first tries from ta-wecutil/etc/local folder and if not from ta-wecutil/etc/default. It is based
    on the script Get-IniContent

    Returns the TA-WECUtil configuration in a hash-table.

.PARAMETER FileName
    Default filename is ta-wecutil_settings.conf

.EXAMPLE 
    Get-WECUtilSettings    

.LINK
     Get-IniContent
    https://devblogs.microsoft.com/scripting/use-powershell-to-work-with-any-ini-file/
#>
function Get-WECUtilSettings {
    Param(  
        [Parameter(ValueFromPipeline=$True)]  
        [ValidateScript({Test-Path $_})]  
        [string]$FileName = "ta-windows-wec_settings.conf" 
    )  

    if (Test-Path "$PSScriptRoot\..\local\$FileName") {
        Get-IniContent "$PSScriptRoot\..\local\$FileName"
    } elseif (Test-Path "$PSScriptRoot\..\default\$FileName") {
        Get-IniContent "$PSScriptRoot\..\default\$FileName"
    } else {
        $null
    }
}


<#
.SYNOPSIS
    Creates the log file.
.DESCRIPTION
    Creates the log file.

    It rotates the existing log file when if it has reached certain size.

.PARAMETER Path
    Path to log file. By default, var/log/splunk/splunk_ta-windows-wec.log.

.PARAMETER MaxSize
    Maximum size in MB from which the log file will rotate. By default, 150MB.

.EXAMPLE 
    Creates a new log file var/log/splunk/splunk_ta-windows-wec.log if it does not exist or
    rotates the existing log file if it reached 50MB
    
    New-WECUtilLogFile -MaxSize 50

.EXAMPLE 
    Creates a new log file var/log/splunk/splunk_ta-windows-wec_custom.log if it does not exist or
    rotates the that log file if it reached the default maximum size.
    
    New-WECUtilLogFile -Path "var/log/splunk/splunk_ta-windows-wec_custom.log"
#>
function New-WECUtilLogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = "$SplunkHome\var\log\splunk\splunk_ta-windows-wec.log",

        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 1000)]
        [int]$MaxSize = 150
    )    

    # Rotate file
    if ((Test-Path $Path)) {
        $LogSize = (Get-Item -Path $Path).Length/1MB
        if ($LogSize -gt $MaxSize) {
            Remove-Item $Path -Force
            New-Item $Path -Force -ItemType File | Out-Null
        }
    } else {
        New-Item $Path -Force -ItemType File | Out-Null
    }
}

<#
.SYNOPSIS
    Writes to log file using Key-Value pair messages.
.DESCRIPTION
    Writes to log file using Key-Value pair messages.

    The messages fall into the following categories: warnings, errors and informational. The format of a message is:

    Timestamp=$Timestamp Level=$Level Function=$Function Message="$m"
    
    All these operations can be performed atomically so that in case of a multithread environment,
    information is not lost and there is not fight for resources.

.PARAMETER Path
    Path to an existing log file.

.PARAMETER Message
    Description of the event to log.

.PARAMETER Function
    Function name where the event happens.

.PARAMETER Level
    Message level. It can be Info, Warn or Error. By default, it is Info.

.PARAMETER UseMutex
    If indicated, all actions are performed atomically: file rotation, file write.

.EXAMPLE 
    It will write an informational message.

    Write-WECUtilLog -Message "informational message" -Function $MyInvocation.MyCommand.Name -UseMutex

.EXAMPLE 
    It will write multiple informational messages.

    "info1", "info2" | Write-WECUtilLog -Function $MyInvocation.MyCommand.Name -UseMutex

.EXAMPLE 
    It will write an warning message.

    Write-WECUtilLog -Message "warning message" -Function $MyInvocation.MyCommand.Name -Level Warn -UseMutex

.LINK
     https://dev.splunk.com/enterprise/docs/developapps/addsupport/logging/loggingbestpractices/
    https://clebam.github.io/2018/02/13/Optimizing-a-Write-Log-function/
    https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7
#>
function Write-WECUtilLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$Path,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Function,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info",

        [Parameter(Mandatory=$false)]
        [switch]$UseMutex
    )

    BEGIN {
        # Start atomic logging action
        if ($UseMutex) {
            try {
                $Mutex = New-Object System.Threading.Mutex($false, "LogMutex")
                [void]$Mutex.WaitOne()
            }
            catch [System.Threading.AbandonedMutexException] {
                # It may happen if a Mutex is not released correctly, but it will still get the Mutex.
            }
        }
    }

    PROCESS {
        foreach ($m in $Message) {
            # Log
            $Timestamp = [DateTime]::UtcNow.ToString('u')
            switch ($Level) {
                'Error' {
                    "Timestamp=$Timestamp Level=$Level Function=$Function Message=`"$m`"" | Out-File -FilePath $Path -Encoding utf8 -Append
                    Write-Error $m
                }
                'Warn' {
                    "Timestamp=$Timestamp Level=$Level Function=$Function Message=`"$m`"" | Out-File -FilePath $Path -Encoding utf8 -Append
                    Write-Warning $m
                }
                'Info' {
                    if ($VerbosePreference -eq 'Continue') {
                        "Timestamp=$Timestamp Level=$Level Function=$Function Message=`"$m`"" | Out-File -FilePath $Path -Encoding utf8 -Append
                    }
                    Write-Verbose $m
                }
            }
        }
    }

    END {
        # End of atomic logging action
        if ($UseMutex) {
            [void]$Mutex.ReleaseMutex()
        }         
    }
}