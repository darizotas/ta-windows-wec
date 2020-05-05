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
    Sets the verbose preference.
.DESCRIPTION
    Sets the verbose preference according to the TA-WECUtil configuration.

    The setting ("log_level") is within the "logging" section. It can be DEBUG or INFO.
    - DEBUG enables Verbose mode ("Continue").
    - INFO is the default PowerShell verbose mode ("SilentlyContinue").

    Errors are redirected to splunk_powershell.ps1.log file.

    Configuration setting:
    [logging]
    ; Log levels: DEBUG = Verbose, NONE = Default (Only warnings and errors)
    ; Errors re redirected to: splunk_powershell.ps1.log
    log_level=DEBUG    

.EXAMPLE 
    Set-WECUtilLoggingPreference

.LINK
     Get-WECUtilSettings
    https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7
#>
function Write-WECUtilLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = "$SplunkHome\var\log\splunk\splunk_ta-windows-wec.log",

        [Parameter(Mandatory=$false)]
        [ValidateRange(10, 1000)]
        [int]$MaxSize = 15,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Function,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info"
    )

    BEGIN {
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

    PROCESS {
        foreach ($m in $Message) {
            # Log
            $Timestamp = [DateTime]::UtcNow.ToString('u')
            switch ($Level) {
                'Error' {
                    "Timestamp=$Timestamp Level=$Level Function=$Function Message=`"$m`"" | Out-File -FilePath $Path -Append
                    Write-Error $m
                }
                'Warn' {
                    "Timestamp=$Timestamp Level=$Level Function=$Function Message=`"$m`"" | Out-File -FilePath $Path -Append
                    Write-Warning $m
                }
                'Info' {
                    if ($VerbosePreference -eq 'Continue') {
                        "Timestamp=$Timestamp Level=$Level Function=$Function Message=`"$m`"" | Out-File -FilePath $Path -Append
                    }
                    Write-Verbose $m
                }
            }
        }
    }
}