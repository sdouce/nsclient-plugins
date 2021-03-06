# ====================================================================
# Check Failover cluster State
# Author: Mathieu Chateau - LOTP
# mail: mathieu.chateau@lotp.fr
# version 0.1
# ====================================================================

#
# Require Set-ExecutionPolicy RemoteSigned.. or sign this script with your PKI 
#
#---------------------------------------------------
$excludeList=@()
$excludeList+='ReportServerTempDB'
$excludeList+='ReportServer'
$isMirrorMandatory=$true
$freespaceWarning=20
$freespaceCritical=10
#---------------------------------------------------
#uncomment to enable debug mode
#$DebugPreference = "Continue"

# ============================================================
#
#  Do not change anything behind that line!
#

$Global:exitcode=0
$output=@()
$performance=@()
$majorError=$false
$instance=""
$specificTest="ALL"
function RaiseAlert ([int]$code)
{
	if($Global:exitcode -lt [int]$code)
	{
		$Global:exitcode=$code
		Write-Debug "Raising exitcode from $Global:exitcode to $code"
	}
}

if(($args[0] -eq "") -or ($args.length -lt 1))
{
	$output+="Error: this script need SQL instance as arg"
	RaiseAlert 2
	$majorError=$true
}
else
{
	$instance=$args[0]
}
if(($args[1] -ne "") -and ($args.length -ge 2))
{
	if($args[1] -match "ALL|FULL|LOG|MIRROR|SPACE")
	{
		$specificTest=$args[1]
	}
	else
	{
		$output+="Error: argument invalid ($args[1]). Possible values:ALL|FULL|LOG|MIRROR|SPACE"
		RaiseAlert 2
		$majorError=$true
	}
}
try
{
	if($majorError -eq $false)
	{
		try
		{
			Write-Debug "Loading SQL module"
			[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO")|out-null
			$source = new-object ('Microsoft.SqlServer.Management.Smo.Server') $($env:COMPUTERNAME+"\$instance")
		}
		catch
		{
		       $output+="major error loading SQL module and connection $_"
		       RaiseAlert 2
		       $majorError=$true
		}
	}

	if ($majorError -eq $false)
	{
		$databases = $source.Databases
		foreach ($database in $databases )
		{
			Write-Debug "doing $($database.Name)"
			if (($excludeList -notcontains $database.Name) -and ($database.IsSystemObject -eq $False))
			{
				if (($database.LastBackupDate -lt (Get-Date).AddDays(-1)) -and ($database.Status -eq [Microsoft.SqlServer.Management.Smo.DatabaseStatus]::Normal) -and ($specificTest -match "ALL|FULL"))
				{
					$output+=$database.Name+": full backup too old ($($database.LastBackupDate))"
					RaiseAlert 2
				}
				if ($database.LastLogBackupDate -lt (Get-Date).Addhours(-1) -and 
				($database.Status -eq [Microsoft.SqlServer.Management.Smo.DatabaseStatus]::Normal) -and
				($database.RecoveryModel -eq [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Full) -and ($specificTest -match "ALL|LOG"))
				{
					$output+=$database.Name+": log backup too old ($($database.LastLogBackupDate))"
					RaiseAlert 2
				}
				if ($database.IsMirroringEnabled -eq $True)
				{
					if ($database.MirroringStatus -ne [Microsoft.SqlServer.Management.Smo.MirroringStatus]::Synchronized -and ($specificTest -match "ALL|MIRROR"))
					{
						$output+=$database.Name+": not synchronized ($($database.MirroringStatus))"
						RaiseAlert 2
					}
					elseif ($database.MirroringWitnessStatus -ne [Microsoft.SqlServer.Management.Smo.MirroringWitnessStatus]::Connected -and ($specificTest -match "ALL|MIRROR"))
					{
						$output+=$database.Name+": witness not connected ($($database.MirroringWitnessStatus))"
						RaiseAlert 1
					}
					
				}
				else
				{
					if($database.Status -ne [Microsoft.SqlServer.Management.Smo.DatabaseStatus]::Normal)
					{
						$output+=$database.Name+": not in good state ($($database.Status))"
						RaiseAlert 2
					}
					elseif ($isMirrorMandatory -and ($specificTest -match "ALL|MIRROR"))
					{
						$output+=$database.Name+": not in mirroring"
						RaiseAlert 2
					}
				}
				if($database.Status -eq [Microsoft.SqlServer.Management.Smo.DatabaseStatus]::Normal -and ($specificTest -match "ALL|SPACE"))
				{
					[int]$DBpercentfree=(100*$database.SpaceAvailable)/($database.SpaceAvailable+$database.DataSpaceUsage+$database.IndexSpaceUsage+1)
					if($DBpercentfree -lt $freespaceCritical)
					{
						$output+=$database.Name+": low free space ($DBpercentfree)"
						RaiseAlert 2
					}
					elseif($DBpercentfree -lt $freespaceWarning )
					{
						$output+=$database.Name+": low free space ($DBpercentfree)"
						RaiseAlert 1
					}
					$performance+="'"+$database.Name+"'"+"="+$DBpercentfree+"%"+";"+$freespaceWarning+";"+$freespaceCritical+" "
				}
			}
		}
	}
}
catch
{
	$exitcode=2
	$majorError=$true
	$output+="Major error during database scan: $_"
}


if($exitcode -eq 0){$state="OK"}
if($exitcode -eq 1){$state="WARNING"}
if($exitcode -eq 2){$state="CRITICAL"}
Write-Host $state" - "$output"|"$performance
exit $exitcode