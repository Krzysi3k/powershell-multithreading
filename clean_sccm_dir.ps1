#
# Clean SCCM cache old folder using runspaces (multithreading)
#

$computers = Get-Content C:\testing\multi_threading\W8-PL.TXT | Where-Object {$_ -match "W8-PL"}
$scriptBlock = {
    Param([string]$computer)
    [datetime]$timePoint = "2016-01-01"
    try
    {
        $result = ls -Path \\$computer\C$\Windows\SysWOW64\CCM\Cache | Where-Object {$_.LastWriteTime -lt $timePoint} -ErrorAction Stop
        if($result) {
            [System.IO.File]::WriteAllLines("C:\testing\multi_threading\Cleanup\removed_files$computer.log", $($result | select Name,LastWriteTime))
            $result | Remove-Item -Recurse -Force
            return "old sccm cache files removed from:$computer"
        } else {
            return $null
        }
    }
    catch
    {
        # catch errors:
        Write-Output "cannot remove files from: $computer" | Out-File C:\testing\multi_threading\Cleanup\err_out_$computer.log -Append
        return "no information from: $computer"
    }
}

function Clean-SCCM-Cache
{
    [CMDletBinding()]Param()
    [int]$maxThreads = 50

    $threads = @()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $runspacePool.ApartmentState = "MTA"
    $runspacePool.Open()

    $watcher = New-Object System.Diagnostics.Stopwatch
    $watcher.Start()
    foreach($comp in $computers)
    {
        $runspaceObject = New-Object PScustomObject @{
            Runspace = [powershell]::Create()
            Invoker = $null
        }
        $runspaceObject.Runspace.RunspacePool = $runspacePool
        $runspaceObject.Runspace.AddScript($scriptBlock) | Out-Null
        $runspaceObject.Runspace.AddArgument($comp) | Out-Null
        $runspaceObject.Invoker = $runspaceObject.Runspace.BeginInvoke()
        $threads += $runspaceObject
        Write-Verbose "execute new thread, $comp, $($watcher.Elapsed)"
    }
    Write-Verbose "processing threads..."
    while ($threads.Invoker.IsCompleted -match $false) {
        Start-Sleep -Milliseconds 20
    }
    Write-Verbose "receiving output and disposing all threads..."
    #$threads_result = @()
    foreach ($t in $threads)
    {
        #$threads_result += $t.Runspace.EndInvoke($t.Invoker)
        $t.Runspace.EndInvoke($t.Invoker)
        $null = $t.Runspace.Dispose
    }
    #$threads_result
    Write-Host "script multithreaded completed $($watcher.Elapsed)"
    $watcher.Stop()
    $runspacePool.Close()
    $runspacePool.Dispose()
}