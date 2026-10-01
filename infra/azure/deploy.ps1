<#
.SYNOPSIS
    Deploys the Cloudflare assessment origin VM on Azure (idempotent).

.DESCRIPTION
    Creates (or updates) a resource group, an NSG locked down to the admin IP (SSH)
    and the Cloudflare edge ranges (HTTPS), and an Ubuntu 24.04 VM with a static
    public IP. Uses an isolated Azure CLI config directory and never runs `az login`.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Harden
    .\deploy.ps1 -AdminIp 203.0.113.10 -VmSizes Standard_D2als_v6
#>
[CmdletBinding()]
param(
    [string]   $ResourceGroup     = 'rg-cf-assessment',
    [string]   $Location          = 'spaincentral',
    [string]   $VmName            = 'vm-cf-origin',
    [string]   $NsgName           = 'nsg-cf-origin',
    [string]   $PublicIpName      = 'pip-cf-origin',
    [string]   $VnetName          = 'vnet-cf-origin',
    [string]   $SubnetName        = 'snet-cf-origin',
    [string]   $AdminUser         = 'azureuser',
    [string]   $SshPublicKeyPath  = "$HOME\.ssh\cf-assessment.pub",
    [string]   $SshPrivateKeyPath = "$HOME\.ssh\cf-assessment",
    # Admin IPv4 allowed to SSH. Auto-detected when empty.
    [string]   $AdminIp           = '',
    # Ordered candidates; the next one is tried on capacity/quota errors.
    [string[]] $VmSizes           = @('Standard_B1s', 'Standard_B1ms', 'Standard_B2s', 'Standard_D2als_v6'),
    [string]   $AzureConfigDir    = $(if ($env:AZURE_CONFIG_DIR) { $env:AZURE_CONFIG_DIR } else { "$HOME\.azure" }),
    [string]   $SubscriptionId    = '',
    [int]      $OsDiskGb          = 30,
    # Run harden.sh on the VM over SSH after deployment.
    [switch]   $Harden
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Image = 'Canonical:ubuntu-24_04-lts:server:latest'
$Tags  = @('project=cf-assessment', 'owner=aforero')

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

function Get-CloudflareRanges {
    param([Parameter(Mandatory)] [string] $Url)
    $ranges = @((Invoke-RestMethod -Uri $Url) -split '\s+' | Where-Object { $_ })
    if ($ranges.Count -eq 0) { throw "No ranges returned by $Url" }
    , $ranges
}

# Creates the NSG rule, or updates its source prefixes if it already exists.
function Set-NsgRule {
    param(
        [Parameter(Mandatory)] [string]   $Name,
        [Parameter(Mandatory)] [int]      $Priority,
        [Parameter(Mandatory)] [int]      $Port,
        [Parameter(Mandatory)] [string[]] $Sources
    )
    $exists = (Invoke-Az -AllowFailure -AzArgs @('network', 'nsg', 'rule', 'show',
            '-g', $ResourceGroup, '--nsg-name', $NsgName, '-n', $Name)).ExitCode -eq 0
    if ($exists) {
        Write-Host "  Updating rule $Name ($($Sources.Count) prefixes)"
        $null = Invoke-Az -AzArgs (@('network', 'nsg', 'rule', 'update',
                '-g', $ResourceGroup, '--nsg-name', $NsgName, '-n', $Name,
                '--priority', $Priority, '--destination-port-ranges', $Port,
                '--source-address-prefixes') + $Sources)
    }
    else {
        Write-Host "  Creating rule $Name ($($Sources.Count) prefixes)"
        $null = Invoke-Az -AzArgs (@('network', 'nsg', 'rule', 'create',
                '-g', $ResourceGroup, '--nsg-name', $NsgName, '-n', $Name,
                '--priority', $Priority, '--direction', 'Inbound', '--access', 'Allow',
                '--protocol', 'Tcp', '--destination-port-ranges', $Port,
                '--source-address-prefixes') + $Sources)
    }
}

# --- Preconditions -----------------------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) not found in PATH.' }

# Never log in from here: an existing session in the isolated profile is required.
$account = Invoke-Az -AllowFailure -AzArgs @('account', 'show', '--query', 'name', '-o', 'tsv')
if ($account.ExitCode -ne 0) {
    throw "No usable Azure session in AZURE_CONFIG_DIR '$AzureConfigDir'. Log in manually with that config dir and re-run.`n$($account.Output)"
}
Write-Host "Subscription: $($account.Output)"

if (-not (Test-Path -LiteralPath $SshPublicKeyPath)) { throw "SSH public key not found: $SshPublicKeyPath" }

if (-not $AdminIp) { $AdminIp = ([string](Invoke-RestMethod -Uri 'https://api.ipify.org')).Trim() }
if ($AdminIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "Invalid admin IPv4 address: '$AdminIp'" }
Write-Host "Admin IP: $AdminIp"

$cfV4 = Get-CloudflareRanges 'https://www.cloudflare.com/ips-v4'
$cfV6 = Get-CloudflareRanges 'https://www.cloudflare.com/ips-v6'

# --- Resource group ----------------------------------------------------------
if ((Invoke-Az -AzArgs @('group', 'exists', '-n', $ResourceGroup)).Output -eq 'true') {
    Write-Host "Resource group $ResourceGroup already exists"
}
else {
    Write-Host "Creating resource group $ResourceGroup in $Location"
    $null = Invoke-Az -AzArgs (@('group', 'create', '-n', $ResourceGroup, '-l', $Location, '--tags') + $Tags)
}

# --- NSG and rules -----------------------------------------------------------
if ((Invoke-Az -AllowFailure -AzArgs @('network', 'nsg', 'show', '-g', $ResourceGroup, '-n', $NsgName)).ExitCode -eq 0) {
    Write-Host "NSG $NsgName already exists"
}
else {
    Write-Host "Creating NSG $NsgName"
    $null = Invoke-Az -AzArgs (@('network', 'nsg', 'create', '-g', $ResourceGroup, '-n', $NsgName, '-l', $Location, '--tags') + $Tags)
}

# IPv4 and IPv6 must be separate rules: Azure rejects mixed address families in one rule.
Set-NsgRule -Name 'allow-ssh-admin'           -Priority 100 -Port 22  -Sources @("$AdminIp/32")
Set-NsgRule -Name 'allow-https-cloudflare-v4' -Priority 110 -Port 443 -Sources $cfV4
Set-NsgRule -Name 'allow-https-cloudflare-v6' -Priority 120 -Port 443 -Sources $cfV6

# --- VM ----------------------------------------------------------------------
if ((Invoke-Az -AllowFailure -AzArgs @('vm', 'show', '-g', $ResourceGroup, '-n', $VmName)).ExitCode -eq 0) {
    Write-Host "VM $VmName already exists"
}
else {
    $created = $false
    foreach ($size in $VmSizes) {
        Write-Host "Creating VM $VmName ($size)"
        $result = Invoke-Az -AllowFailure -AzArgs (@('vm', 'create',
                '-g', $ResourceGroup, '-n', $VmName, '-l', $Location,
                '--image', $Image, '--size', $size,
                '--admin-username', $AdminUser, '--ssh-key-values', $SshPublicKeyPath,
                '--authentication-type', 'ssh',
                '--public-ip-address', $PublicIpName, '--public-ip-sku', 'Standard',
                '--public-ip-address-allocation', 'static',
                '--vnet-name', $VnetName, '--subnet', $SubnetName, '--nsg', $NsgName,
                '--os-disk-size-gb', $OsDiskGb, '--storage-sku', 'Standard_LRS',
                '--tags') + $Tags)
        if ($result.ExitCode -eq 0) { $created = $true; break }

        # Only capacity/quota problems justify trying the next size.
        if ($result.Output -match 'SkuNotAvailable|QuotaExceeded|AllocationFailed|exceeding approved .*quota') {
            Write-Warning "$size not available in $Location (capacity/quota); trying next size."
            continue
        }
        throw "VM creation failed with ${size}:`n$($result.Output)"
    }
    if (-not $created) { throw "None of the candidate sizes could be deployed in ${Location}: $($VmSizes -join ', ')" }
}

$vmSize   = (Invoke-Az -AzArgs @('vm', 'show', '-g', $ResourceGroup, '-n', $VmName, '--query', 'hardwareProfile.vmSize', '-o', 'tsv')).Output
$publicIp = (Invoke-Az -AzArgs @('vm', 'show', '-d', '-g', $ResourceGroup, '-n', $VmName, '--query', 'publicIps', '-o', 'tsv')).Output
Write-Host "VM size:   $vmSize"
Write-Host "Public IP: $publicIp"

# --- Optional OS hardening ---------------------------------------------------
if ($Harden) {
    if (-not $publicIp) { throw 'VM has no public IP (is it deallocated?); cannot harden.' }
    if (-not (Test-Path -LiteralPath $SshPrivateKeyPath)) { throw "SSH private key not found: $SshPrivateKeyPath" }
    $hardenPath = Join-Path $PSScriptRoot 'harden.sh'

    # Strip CR so bash accepts the script. PowerShell appends a CRLF when piping to a
    # native command, so a trailing comment line absorbs that stray CR.
    $script = ((Get-Content -Raw -LiteralPath $hardenPath) -replace "`r", '').TrimEnd() + "`n# eof"

    Write-Host "Hardening $VmName over SSH"
    $script | & ssh -i $SshPrivateKeyPath -o StrictHostKeyChecking=accept-new "$AdminUser@$publicIp" "sudo bash -s -- $AdminIp"
    if ($LASTEXITCODE -ne 0) { throw "Hardening failed (ssh exit $LASTEXITCODE)." }
}

Write-Host "Done. Connect with: ssh -i $SshPrivateKeyPath $AdminUser@$publicIp"
