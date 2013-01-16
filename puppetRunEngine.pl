#!/usr/bin/perl


use lib "/usr/local/bin/modules";
use MysqlConnection;
use LogFile;


my $mysqlConn; my $mysqlError; my $query;  my $mysqlHash;
my $command; my $retCode; my $now; my $ipAddress; my $pupId;
my $sendStatusNullCount = 0; my $retValue; my $passedTime;
my $log = LogFile->new();
$log->InitLogFile("/usr/local/bin/puppetEngine.log");
$log->AddLogLine("Start new run..............");
$mysqlConn = MysqlConnection->new();
$mysqlError = $mysqlConn->StartConnection();
if($mysqlError == 10)
{
	print "Mysql connection is not OK\n";
	$log->AddLogLine("Problem with mysql connection");
        exit(1);
}
$query = "select * from puppetrun where send_status is null or send_status='SentError'";
$mysqlConn->SetMakeQuery($query);
while($mysqlHash = $mysqlConn->GetHashrow())
{
	$ipAddress = $mysqlHash->{ip};
	$pupId = $mysqlHash->{id};
	$sendStatusNullCount++;
	$log->AddLogLine("Send puppet command to $mysqlHash->{ip}");
	$command = "timeout  60 ssh -i \"/var/lib/.dagmar/.dagmar\" -o \"GlobalKnownHostsFile /dev/null\" -o StrictHostKeyChecking=no sysops\@$ipAddress \"echo 1 > /var/tmp/runPuppetClient\"";
	$retCode  = system("$command");
	$log->AddLogLine("C=$command");
	$log->AddLogLine("RetCode=$retCode");
	if($retCode >= 1)
	{
		#an error was encountered, this must be marked in mysql
		$now = $log->DateTime();
		$query = "update puppetrun set run_status_date='$now',send_status='SentError' where id=$pupId";
		$mysqlConn->SetMakeQuerySecondary("$query");
		$mysqlConn->EndQuerySecondary();	
	}
	else
	{
		#all looks ok,mark this in mysql as ok
		$now = $log->DateTime(); 
		$query = "update puppetrun set run_status_date='$now',send_status='SentOK' where id=$pupId";
		$mysqlConn->SetMakeQuerySecondary("$query");
		$mysqlConn->EndQuerySecondary();
	}
}
$mysqlConn->EndQuery();
$query = "select *,now()-send_date as passed_time from puppetrun where send_status  like '%SentOK%'";
$mysqlConn->SetMakeQuery($query);
while($mysqlHash = $mysqlConn->GetHashrow())
{
	$ipAddress = $mysqlHash->{ip};
	$pupId = $mysqlHash->{id};
	$passedTime = $mysqlHash->{passed_time}; 	##in seconds
	$passedTime = $passedTime / 60; 		##in minutes
	$command = "timeout  60 ssh -i \"/var/lib/.dagmar/.dagmar\" -o \"GlobalKnownHostsFile /dev/null\" -o StrictHostKeyChecking=no sysops\@$ipAddress \"cat /var/tmp/runPuppetClient\"";
	$log->AddLogLine("C=$command");
	$retValue = `$command`;
	$retValue =~ s/\n//g;
	$log->AddLogLine("RetValue=$retValue;passedTime=$passedTime minutes");
	if($passedTime > 600 and $retValue >= 1)
	{
		$log->AddLogLine("Too much time has passed since last command was sent.Set on error.");
		$query = "update puppetrun set send_status='SentOK_WP',comment='Too much time since SentOK was set' where id=$pupId";
		$mysqlConn->SetMakeQuerySecondary($query);
		$mysqlConn->EndQuerySecondary();
	}
	elsif(!$retValue)
	{
		$log->AddLogLine("Puppet runned succesfully. Time passed=$passedTime");
		$now = $log->DateTime();
		$query = "update puppetrun set send_status='Exec_OK',comment='All looks OK' where id=$pupId";
		$mysqlConn->SetMakeQuerySecondary($query);
		$mysqlConn->EndQuerySecondary();
	}	
}
$mysqlConn->EndQuery();

if(!$sendStatusNullCount) {$log->AddLogLine("send_status NULL count = $sendStatusNullCount");}
$mysqlConn->StopConnection();
$log->AddLogLine("Stop the run......");
