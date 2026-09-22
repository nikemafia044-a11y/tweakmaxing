<#
.SYNOPSIS
    Roda a suite Pester do TweakMaxing.
.EXAMPLE
    .\tests\Invoke-Tests.ps1
.EXAMPLE
    .\tests\Invoke-Tests.ps1 -Tag Rollback
#>
[CmdletBinding()]
param(
    [string[]] $Path = $PSScriptRoot,
    [string[]] $Tag,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string] $Verbosity = 'Detailed'
)

Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path         = $Path
$config.Run.Exit         = $true
$config.Output.Verbosity = $Verbosity
if ($Tag) { $config.Filter.Tag = $Tag }

Invoke-Pester -Configuration $config
