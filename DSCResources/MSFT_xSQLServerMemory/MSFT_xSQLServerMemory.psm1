Import-Module -Name (Join-Path -Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -ChildPath 'xSQLServerHelper.psm1') -Force

<#
    .SYNOPSIS
    This function gets the value of the min and max memory server configuration option.

    .PARAMETER SQLServer
    The host name of the SQL Server to be configured.

    .PARAMETER SQLInstanceName
    The name of the SQL instance to be configured.
#>

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLInstanceName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLServer = $env:COMPUTERNAME
    )

    $sqlServerObject = Connect-SQL -SQLServer $SQLServer -SQLInstanceName $SQLInstanceName

    if ($sqlServerObject)
    {
        Write-Verbose -Message 'Getting the value for minimum and maximum SQL server memory.'
        $minMemory = $sqlServerObject.Configuration.MinServerMemory.ConfigValue
        $maxMemory = $sqlServerObject.Configuration.MaxServerMemory.ConfigValue
    }

    $returnValue = @{
        SQLInstanceName = $SQLInstanceName
        SQLServer       = $SQLServer
        MinMemory       = $minMemory
        MaxMemory       = $maxMemory
    }

    $returnValue
}

<#
    .SYNOPSIS
    This function sets the value for the min and max memory server configuration option.

    .PARAMETER SQLServer
    The host name of the SQL Server to be configured.

    .PARAMETER SQLInstanceName
    The name of the SQL instance to be configured.
    
    .PARAMETER Ensure
    When set to 'Present' then min and max memory will be set to either the value in parameter MinMemory and MaxMemory or dynamically configured when parameter DynamicAlloc is set to $true.
    When set to 'Absent' min and max memory will be set to default values.

    .PARAMETER DynamicAlloc
    If set to $true then max memory will be dynamically configured.
    When this is set parameter is set to $true, the parameter MaxMemory must be set to $null or not be configured.

    .PARAMETER MinMemory
    This is the minimum amount of memory, in MB, in the buffer pool used by the instance of SQL Server.

    .PARAMETER MaxMemory
    This is the maximum amount of memory, in MB, in the buffer pool used by the instance of SQL Server.
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLInstanceName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLServer = $env:COMPUTERNAME,

        [Parameter()]
        [ValidateSet('Present','Absent')]
        [System.String]
        $Ensure = 'Present',

        [Parameter()]
        [System.Boolean]
        $DynamicAlloc = $false,

        [Parameter()]
        [System.Int32]
        $MinMemory,
        
        [Parameter()]
        [System.Int32]
        $MaxMemory
    )

    $sqlServerObject = Connect-SQL -SQLServer $SQLServer -SQLInstanceName $SQLInstanceName
    
    if ($sqlServerObject)
    {
        Write-Verbose -Message 'Setting the minimum and maximum memory used by the instance.'
        switch ($Ensure)
        {
            'Present'
            {
                if ($DynamicAlloc)
                {
                    if ($MaxMemory)
                    {
                        throw New-TerminatingError -ErrorType MaxMemoryParamMustBeNull `
                                                   -FormatArgs @( $SQLServer,$SQLInstanceName ) `
                                                   -ErrorCategory InvalidArgument  
                    }

                    $MaxMemory = Get-SqlDscDynamicMaxMemory
                    New-VerboseMessage -Message "Dynamic maximum memory has been calculated to $($MaxMemory)MB."
                }
                else
                {
                    if (-not $MaxMemory)
                    {
                        throw New-TerminatingError -ErrorType MaxMemoryParamMustNotBeNull `
                                                   -FormatArgs @( $SQLServer,$SQLInstanceName ) `
                                                   -ErrorCategory InvalidArgument  
                    }
                }

                $sqlServerObject.Configuration.MaxServerMemory.ConfigValue = $MaxMemory
                New-VerboseMessage -Message "Maximum memory used by the instance has been limited to $($MaxMemory)MB."
            }
            
            'Absent'
            {
                $sqlServerObject.Configuration.MaxServerMemory.ConfigValue = 2147483647
                $sqlServerObject.Configuration.MinServerMemory.ConfigValue = 0
                New-VerboseMessage -Message ('Ensure is set to absent. Minimum and maximum server memory' + `
                                             'values used by the instance are reset to the default values.')
            }
        }

        try
        {
            if ($MinMemory)
            {
                $sqlServerObject.Configuration.MinServerMemory.ConfigValue = $MinMemory
                New-VerboseMessage -Message "Minimum memory used by the instance is set to $($MinMemory)MB."
            }

            $sqlServerObject.Alter()
        }
        catch
        {
            throw New-TerminatingError -ErrorType AlterServerMemoryFailed `
                                       -FormatArgs @($SQLServer,$SQLInstanceName) `
                                       -ErrorCategory InvalidOperation `
                                       -InnerException $_.Exception
        }
    }
}

<#
    .SYNOPSIS
    This function tests the value of the min and max memory server configuration option.

    .PARAMETER SQLServer
    The host name of the SQL Server to be configured.

    .PARAMETER SQLInstanceName
    The name of the SQL instance to be configured.
    
    .PARAMETER Ensure
    When set to 'Present' then min and max memory will be set to either the value in parameter MinMemory and MaxMemory or dynamically configured when parameter DynamicAlloc is set to $true.
    When set to 'Absent' min and max memory will be set to default values.

    .PARAMETER DynamicAlloc
    If set to $true then max memory will be dynamically configured.
    When this is set parameter is set to $true, the parameter MaxMemory must be set to $null or not be configured.

    .PARAMETER MinMemory
    This is the minimum amount of memory, in MB, in the buffer pool used by the instance of SQL Server.

    .PARAMETER MaxMemory
    This is the maximum amount of memory, in MB, in the buffer pool used by the instance of SQL Server.
#>
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLInstanceName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLServer = $env:COMPUTERNAME,

        [Parameter()]
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = 'Present',

        [Parameter()]
        [System.Boolean]
        $DynamicAlloc = $false,

        [Parameter()]
        [System.Int32]
        $MinMemory,

        [Parameter()]
        [System.Int32]
        $MaxMemory
    )

    Write-Verbose -Message 'Testing the values of the minimum and maximum memory server configuration option set to be used by the instance.'  

    $getTargetResourceParameters = @{
        SQLInstanceName = $PSBoundParameters.SQLInstanceName
        SQLServer       = $PSBoundParameters.SQLServer
    }

    $getTargetResourceResult = Get-TargetResource @getTargetResourceParameters
    
    $currentMinMemory = $getTargetResourceResult.MinMemory
    $currentMaxMemory = $getTargetResourceResult.MaxMemory
    $isServerMemoryInDesiredState = $true

    switch ($Ensure)
    {
        'Absent'
        {
            if ($currentMaxMemory -ne 2147483647)
            {
                New-VerboseMessage -Message "Current maximum server memory used by the instance is $($currentMaxMemory)MB. Expected 2147483647MB."
                $isServerMemoryInDesiredState = $false
            }

            if ($currentMinMemory -ne 0)
            {
                New-VerboseMessage -Message "Current minimum server memory used by the instance is $($currentMinMemory)MB. Expected 0MB."
                $isServerMemoryInDesiredState = $false
            }
        }

        'Present'
        {
            if ($DynamicAlloc)
            {
                if ($MaxMemory)
                {
                    throw New-TerminatingError -ErrorType MaxMemoryParamMustBeNull `
                                               -FormatArgs @( $SQLServer,$SQLInstanceName ) `
                                               -ErrorCategory InvalidArgument  
                }

                $MaxMemory = Get-SqlDscDynamicMaxMemory
                New-VerboseMessage -Message "Dynamic maximum memory has been calculated to $($MaxMemory)MB."
            }
            else
            {
                if (-not $MaxMemory)
                {
                    throw New-TerminatingError -ErrorType MaxMemoryParamMustNotBeNull `
                                               -FormatArgs @( $SQLServer,$SQLInstanceName ) `
                                               -ErrorCategory InvalidArgument  
                }
            }

            if ($MaxMemory -ne $currentMaxMemory)
            {
                New-VerboseMessage -Message ("Current maximum server memory used by the instance " + `
                                             "is $($currentMaxMemory)MB. Expected $($MaxMemory)MB.")
                $isServerMemoryInDesiredState = $false
            }

            if ($MinMemory)
            {
               if ($MinMemory -ne $currentMinMemory)
                {
                    New-VerboseMessage -Message ("Current minimum server memory used by the instance " + `
                                                 "is $($currentMinMemory)MB. Expected $($MinMemory)MB.")
                    $isServerMemoryInDesiredState = $false
                }
            }
        }
    }

    return $isServerMemoryInDesiredState
}

<#
    .SYNOPSIS
    This cmdlet is used to return the Dynamic MaxMemory of a SQL Instance
#>
function Get-SqlDscDynamicMaxMemory
{
    try
    {
        $physicalMemory = ((Get-CimInstance -ClassName Win32_PhysicalMemory).Capacity | Measure-Object -Sum).Sum
        $physicalMemoryInMegaBytes = [Math]::Round($physicalMemory / 1MB)
        
        # Find how much to save for OS: 20% of total ram for under 15GB / 12.5% for over 20GB
        if ($physicalMemoryInMegaBytes -ge 20480)
        {
            $reservedOperatingSystemMemory = [Math]::Round((0.125 * $physicalMemoryInMegaBytes))
        }
        else
        {
            $reservedOperatingSystemMemory = [Math]::Round((0.2 * $physicalMemoryInMegaBytes))
        }

        $numberOfCores = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum

        # Get the number of SQL threads.
        if ($numberOfCores -ge 4)
        {
            $numberOfSqlThreads = 256 + ($numberOfCores - 4) * 8
        }
        else
        {
            $numberOfSqlThreads = 0
        }

        $operatingSystemArchitecture = (Get-CimInstance -ClassName Win32_operatingsystem).OSArchitecture
        
        # Find threadStackSize 1MB x86/ 2MB x64/ 4MB IA64
        if ($operatingSystemArchitecture -eq '32-bit')
        {
            $threadStackSize = 1
        }
        elseif ($operatingSystemArchitecture -eq '64-bit')
        {
            $threadStackSize = 2
        }
        else
        {
            $threadStackSize = 4
        }

        $maxMemory = $physicalMemoryInMegaBytes - $reservedOperatingSystemMemory - ($numberOfSqlThreads * $threadStackSize) - (1024 * [System.Math]::Ceiling($numberOfCores / 4))
    }
    catch
    {
        throw New-TerminatingError -ErrorType ErrorGetDynamicMaxMemory `
                                   -ErrorCategory InvalidOperation `
                                   -InnerException $_.Exception
    }

    $maxMemory
}

Export-ModuleMember -Function *-TargetResource
