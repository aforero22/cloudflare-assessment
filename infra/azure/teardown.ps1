<#
.SYNOPSIS
    Deletes the assessment resource group and everything in it.

.EXAMPLE
    .\teardown.ps1
    .\teardown.ps1 -Force -NoWait
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup  = 'rg-cf-assessment',
    [string] $AzureConfigDir = $(if ($env:AZURE_CONFIG_DIR) { $env:AZURE_CONFIG_DIR } else { "$HOME\.azure" }),
    [string] $SubscriptionId = '',
    # Skip the interactive confirmation.
    [switch] $Force,
    # Return immediately instead of waiting for the deletion to finish.
    [switch] $NoWait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Every az call in this session uses the isolated CLI profile.
$env:AZURE_CONFIG_DIR = $AzureConfigDir

# Runs az and returns exit code + combined output. Native stderr must not become a
# terminating error, so the preference is relaxed locally and the exit code is checked.
function Invoke-Az {
    param(
        [Parameter(Mandatory)] [string[]] $AzArgs,
        [switch] $AllowFailure
    )
    $ErrorActionPreference = 'Continue'
    $all = $AzArgs + @('--only-show-errors')
    if ($SubscriptionId) { $all += @('--subscription', $SubscriptionId) }
    $out  = & az @all 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $text = (@($out) -join "`n").Trim()
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "az $($AzArgs -join ' ') failed (exit $code):`n$text"
    }
    [pscustomobject]@{ ExitCode = $code; Output = $text }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) not found in PATH.' }

# Never log in from here: an existing session in the isolated profile is required.
$account = Invoke-Az -AllowFailure -AzArgs @('account', 'show', '--query', 'name', '-o', 'tsv')
if ($account.ExitCode -ne 0) {
    throw "No usable Azure session in AZURE_CONFIG_DIR '$AzureConfigDir'. Log in manually with that config dir and re-run.`n$($account.Output)"
}
Write-Host "Subscription: $($account.Output)"

if ((Invoke-Az -AzArgs @('group', 'exists', '-n', $ResourceGroup)).Output -ne 'true') {
    Write-Host "Resource group $ResourceGroup does not exist; nothing to delete."
    return
}

if (-not $Force) {
    $answer = Read-Host "Delete resource group '$ResourceGroup' and ALL its resources? Type the group name to confirm"
    if ($answer -ne $ResourceGroup) {
        Write-Host 'Aborted.'
        return
    }
}

$deleteArgs = @('group', 'delete', '-n', $ResourceGroup, '--yes')
if ($NoWait) { $deleteArgs += '--no-wait' }

Write-Host "Deleting resource group $ResourceGroup"
$null = Invoke-Az -AzArgs $deleteArgs

if ($NoWait) { Write-Host 'Deletion started (running in the background).' }
else { Write-Host 'Resource group deleted.' }
