# ====================================================================
# Search in AD for lockedout account. To be used through NRPE / nsclient++
# Author: Mathieu Chateau - LOTP
# mail: mathieu.chateau@lotp.fr
# version 0.3
# ====================================================================

#
# Require Set-ExecutionPolicy RemoteSigned.. or sign this script with your PKI 
#

# ============================================================
#
#  Do not change anything behind that line!
#
param 
(
	[string]$action = "LockedOut",
	[string]$searchBase = "",
	[string]$searchScope = "Subtree",
	[int]$maxWarn = 5,
	[int]$maxCrit = 10,
	[string] $samaccountname="*"
)

# check that powershell ActiveDirectory module is present
if(Get-Module -Name "ActiveDirectory" -ListAvailable)
{
	try
	{
		Import-Module -Name ActiveDirectory
	}
	catch
	{
		Write-Host "CRITICAL: Missing PowerShell ActiveDirectory module"
		exit 2
	}
}
else
{
	Write-Host "CRITICAL: Missing PowerShell ActiveDirectory module"
	exit 2
}

# check params if provided
if($action -notmatch "^(AccountDisabled|AccountExpired|AccountExpiring|AccountInactive|LockedOut|PasswordExpired|PasswordNeverExpires)$")
{
	Write-Host "CRITICAL: action parameter can only be AccountDisabled,AccountExpired,AccountExpiring,AccountInactive,LockedOut,PasswordExpired,PasswordNeverExpires. Provided $action"
	exit 2
}
if($searchScope -notmatch "^(Base|OneLevel|Subtree)$")
{
	Write-Host "CRITICAL: searchScope parameter can only be Base,OneLevel,Subtree. Provided $searchScope"
	exit 2
}
if(($searchBase -ne "") -and $searchBase -ne ((Get-ADDomain).DistinguishedName))
{
	$search=Get-ADObject -Filter 'ObjectClass -eq "OrganizationalUnit" -and DistinguishedName -eq $searchBase'
	if ($search.Count -ne 1)
	{
		Write-Host "CRITICAL: SearchBase not found or duplicate. Provided $searchBase"
		exit 2
	}
}
else
{
	$searchBase=(Get-ADDomain).DistinguishedName
}

$command="Search-ADAccount -"+$action+" -SearchBase '"+$searchBase+"' -SearchScope "+$searchScope
$result=invoke-expression $command
$fileteredResults=@()
foreach ($entry in $result)
{
	if(($samaccountname -eq $null) -or ($samaccountname -eq "*") -or ($samaccountname -eq "") -or ($entry.SamAccountName -match $samaccountname))
	{
		$fileteredResults+=$entry
	}
}
if($fileteredResults.Count -gt $maxCrit)
{
	$state="CRITICAL"
	$exitcode=2
}
elseif($fileteredResults.Count -gt $maxWarn)
{
	$state="WARNING"
	$exitcode=1
}
else
{
	$state="OK"
	$exitcode=0
}

$output=$state+": "+$fileteredResults.Count+" "+$action+"|"+$action+"="+$fileteredResults.Count+";"+$maxWarn+";"+$maxCrit
Write-Host $output
exit $exitcode
