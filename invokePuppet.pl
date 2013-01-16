#!/usr/bin/perl

use Date::Parse;
use Date::Format;

my $logFileName = "/var/log/invokePuppet.log"; 
my $puppetTempLog = "/usr/local/bin/invokePuppet/puppetTempLog.log";
my $logFileHander; my $dateTime;
my $availMem; my $amuleStatus; my $invokePuppetRetCode;
my $statusHandle; my $statusFile="/usr/local/bin/invokePuppet.status";
my $runPuppetODFile = "/var/tmp/runPuppetClient"; my $runPuppetODHandler;
my $runPuppetClient = 0; my $pidFile="/var/tmp/invokePuppet.pid"; my $pidHandle;
my $pidContent; my $myOwnPid;
#####################################################################
$dateTime = GetDate()." ".GetTime();
LogAction("$dateTime -- Start.....");
open($pidHandle,"<",$pidFile);
$pidContent = <$pidHandle>;
LogAction("$dateTime -- pidContent=$pidContent");
close($pidFile);
if(!$pidContent)
{
	$myOwnPid = $$;
	LogAction("Looks like there no other process running --myOwnPid=$myOwnPid");
	open($pidHandle,">",$pidFile);
	print $pidHandle "$myOwnPid=$dateTime";
	close($pidHandle);
	LogAction("Write  pid file with:--$myOwnPid=$dateTime");
}
else
{
	my $oldTime; my @tempData = (); my $diffTime; my $oldPid;
	LogAction("Another process already exists: $pidContent");	
	@tempData = split('=',$pidContent);
	$oldTime = $tempData[1];
	$oldPid = $tempData[0];
	$diffTime = str2time($dateTime) - str2time($oldTime);
	LogAction("DiffTime = $diffTime, oldPid=$oldPid");
	if($diffTime >= 7200)
	{
		LogAction("The old process is older than 3 hours. Old process must be killed.");
		`kill -9 $oldPid 2>/dev/null`;
		open($pidHandle,">",$pidFile);
		close($pidHandle);
	}
	else 
	{
		LogAction("Another process is running. Must wait some time...\n##############");
		exit 0;
	}
}
###
ResetPuppetLog();
#####################################################################
open($runPuppetODHandler,"<",$runPuppetODFile);
if(!$runPuppetODHandler or $! =~ "such file or dir")
{
	LogAction("The runPuppetODFile is not here. Nothing to do.\n##############");
        open($pidHandle,">",$pidFile);
        close($pidHandle);	
	exit 0;
}
LogAction("Error from file: $!..");
$runPuppetClient = <$runPuppetODHandler>;
LogAction("runPuppetODFile is here...Value=$runPuppetClient");
close($runPuppetODHandler);
if($runPuppetClient != 1)
{
	LogAction("Puppet will not run this time.\n##############");
	close($statusHandle);
        open($pidHandle,">",$pidFile);
        close($pidHandle);			
	exit 0;
}
#####################################################################
$availMem = CheckAvailableMemory();				##get available memory (free mem) to if we can run puppet 
LogAction("AvailableMemory=$availMem");
if($availMem < 200000)						##avail mem < 200000KB, must stop amule, then run puppet , then start amule
{
	$amuleStatus = 1;					##presume that amule is running
	StopAmule();
	if($amuleStatus != 2)					##amule is still running, we can't free up mem
	{
		LogAction("Unable to stop amule.Must exit....\n#######################");
		exit 1;
	}
	StartAmule();
	if($amuleStatus != 1)
	{
		LogAction("Unable to start amule. Go on puppet.....");
	}
	$invokePuppetRetCode = InvokePuppet();
}
else
{
	$invokePuppetRetCode = InvokePuppet();
}
if($invokePuppetRetCode >= 1) 
{
	open($statusHandle,">","$statusFile");
	print $statusHandle "Fail";
	close($statusHandle);
	open($runPuppetODHandler,">",$runPuppetODFile);
	print $runPuppetODHandler "2";
	close($runPuppetODHandler);
	exit 1;
}
open($statusHandle,">","$statusFile");
print $statusHandle "Success";
close($statusHandle);
open($runPuppetODHandler,">",$runPuppetODFile);
print $runPuppetODHandler "0";
close($runPuppetODHandler);
###
$dateTime = GetDate()." ".GetTime();
LogAction("--$dateTime -- Remove content from pidfile");
open($pidHandle,">",$pidFile);
close($pidHandle);
LogAction("$dateTime -- End.....\n########################\n");
exit 0;
#####################################################################
sub InvokePuppet
{
	my $puppetCycleRetCode; my $maxCycles = 5;
	my $parsePuppetLogRetCode; my $keepGoing = 1;
	my $count = 0; my $puppetRunStatus;
	do
	{
		LogAction("Start new puppet cycle...$count");
		$puppetCycleRetCode = PuppetCycle();
		if($puppetCycleRetCode < 1)
		{
			LogAction("Start puppet parse log");
			$parsePuppetLogRetCode = ParsePuppetLog();
			LogAction("ParsePuppetLogRetCode = $parsePuppetLogRetCode");
			if($parsePuppetLogRetCode > 0) 
			{
				LogAction("parsePuppetLog is positive: $parsePuppetLogRetCode ...Looks OK");
				$keepGoing++;
				$puppetRunStatus = 1; ## puppet was successfull
			}
		}
		$count++;
	}while($count < $maxCycles and $keepGoing == 1);
	if($keepGoing == 1) {return 1;} ## puppet was unsuccessfull
	return 0;
}

sub ParsePuppetLog
{
	my $fileHandle; my $line; my $goodFactor = 0; 
	open($fileHandle,"<",$puppetTempLog);
	while($line = <$fileHandle>)
	{
		if($line =~ "SSL_connect SYSCALL") {$goodFactor -= 1000; LogAction("SSL problem found");}
		if($line =~ "Could not retrieve catalog; skipping run") {$goodFactor -= 500; LogAction("skipping run problem found");}
		if($line =~ "failed dependencies") {$goodFactor -= 1000; LogAction("failed dependencies problem found");}
		if($line =~ "Applying configuration version") {$goodFactor += 10; LogAction("ok log found");}
		if($line =~ "Finished catalog run in") {$goodFactor += 10; LogAction("ok log found");}
	}
	close($fileHandle);
	return $goodFactor;
}

sub PuppetCycle
{
        my $maxIterStepOne = 20; my $startPuppet=1; my $count=0;
        my $puppetPid; my $maxIterStepTwo = 100;
        my $puppetCmd = "/usr/sbin/puppetd -v -o -l $puppetTempLog";
	ResetPuppetLog();
        `$puppetCmd`;
        do
        {
                $puppetPid = GetPuppetPid();
                if($puppetPid > 1)
                {
                        $startPuppet++;
                        LogAction("Puppet is running");
                }
                $count++;
                sleep(1);
        }while($count < $maxIterStepOne and $startPuppet == 1);
        $count=0;
	if($startPuppet == 1)
	{
		LogAction("Puppet did not start in $maxIterStepOne seconds. Maybe there is a problem");
		return 1;
	}
        do
        {
                $puppetPid = GetPuppetPid();
                if($puppetPid == 1)
                {
                        $startPuppet++;
                        LogAction("Puppet is done now");
                }
                $ount++;
                sleep(1);
        }while($count < $maxIterStepTwo and $startPuppet == 2);	
	if($startPuppet == 2)
	{
		LogAction("Puppet did not end in $maxIterStepTwo seconds. Maybe there is a problem");
		return 2;
	}
	return 0;
}

sub StopAmule 
{
	my $amulePid; my $maxIter=10; my $count=0;
	$amulePid = GetAmulePid();
	if($amulePid == 1) {return;}
	do
	{
		`kill $amulePid`;
		sleep(1);
		$amulePid = GetAmulePid();
		if($amulePid == 1) 
		{
			$amuleStatus = 2;
			LogAction("Amule was killed");
		}
		$count++;
	}while($count < $maxIter and $amuleStatus == 1);
}

sub StartAmule
{
	my $amulePid; my $maxIter=60; my $count=0;
	$amulePid = GetAmulePid();
	if($amulePid > 1)
	{
		$amuleStatus = 1; ##amules running
		return 0;
	}
	`/home/amule/run/run.sh`;
	do 
	{
		$amulePid = GetAmulePid();
		$count++;
		sleep(1);
	}while($count < $maxIter and $amulePid > 1);
	if($amulePid == 1) 
	{
		$amuleStatus = 2;	
		return 1;
	}
	$amuleStatus = 1;
	return 0;
}	

sub GetAmulePid
{
	my $amulePid; my @files = (); my $directory; my $fileName = "cmdline";
	@files = </proc/*>; my $textDir; my $cmdFileName;
	my $cmdFileHandler; my $line;
        foreach $directory (@files)
        {
                $textDir = $directory;
                $textDir =~ s/\/proc\///;
                if($textDir =~ m/^[1-9]+/)
                {
                        $cmdFileName = $directory."/".$fileName;
#                       LogAction("It is a pid dir... -- $cmdFileName");
                        open($cmdFileHandler,"<",$cmdFileName);
                        $line = <$cmdFileHandler>;
#                       LogAction("It is a pid dir...(T=$textDir) -- $cmdFileName -- $line");
                        close($cmdFileHandler);
                        if($line =~ "amuled" and $line =~ "run" and $line =~ "-f" and $line =~ "src")
                        {
                                $amulePid = $textDir;
                                last;
                        }
                }
        }
        if(!$amulePid) {return 1;}
        LogAction("Amule PID found=$amulePid");
	return $amulePid;
}

sub GetPuppetPid
{
	my $puppetPid; my @files = (); my $directory; my $fileName = "cmdline";
	@files = </proc/*>; my $textDir; my $cmdFileName;
        my $cmdFileHandler; my $line;
        foreach $directory (@files)
        {
                $textDir = $directory;
                $textDir =~ s/\/proc\///;
                if($textDir =~ m/^[1-9]+/)
                {
                        $cmdFileName = $directory."/".$fileName;
#                       LogAction("It is a pid dir... -- $cmdFileName");
                        open($cmdFileHandler,"<",$cmdFileName);
                        $line = <$cmdFileHandler>;
#                       LogAction("It is a pid dir...(T=$textDir) -- $cmdFileName -- $line");
                        close($cmdFileHandler);
                        if($line =~ "puppetd" and $line =~ "-v" and $line =~ "-o" and $line =~ "-l")
                        {
                                $puppetPid = $textDir;
                                last;
                        }
                }
        }
        if(!$puppetPid) {return 1;}
        LogAction("Puppet PID found=$puppetPid");
        return $puppetPid;
}

sub CheckAvailableMemory
{
	my $tempFileName = "/proc/meminfo";
	my $tempFileHandle; my $line; my $tempMem; my @tempTextPart;
	open($tempFileHandle,"<",$tempFileName);
	while($line = <$tempFileHandle>)
	{
		$line =~ s/\n//g;
		if($line =~ "MemFree")
		{
			@tempTextPart = split(':',$line);
			$tempMem = $tempTextPart[1];
			$tempMem =~ s/[a-z][A-Z]//g;
			$tempMem =~ s/ //g;
			last;
		}
	}
	close();
	return $tempMem;
}

sub ResetPuppetLog
{
	my $puppetLogHandler;
	open($puppetLogHandler,">",$puppetTempLog);
	close($puppetLogHandler);
}

sub LogAction
{
	my $msg = shift;
	open($logFileHander,">>","$logFileName");
	print $logFileHander "..$msg\n";
	close($logFileHander);
}

sub GetDate
{
        my @time = localtime(time());
        $time[4] = $time[4] + 1;         ##luna
        $time[5] = $time[5] + 1900;      ##anul
        if($time[4] < 9) {$time[4] = "0$time[4]";}
        if($time[3] < 9) {$time[3] = "0$time[3]";}
        my $timp = "$time[5]-$time[4]-$time[3]";
        return $timp;
}

sub GetTime
{
        my @time = localtime(time());
        if($time[0] < 10) {$time[0] = "0$time[0]";}
        if($time[1] < 10) {$time[1] = "0$time[1]";}
        my $timp = "$time[2]:$time[1]:$time[0]";
        return $timp;
}

