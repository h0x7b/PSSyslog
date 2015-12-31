# PSSyslog
Powershell syslog client

Description
===========
This is a simple Powershell syslog client.

Features and limitations
=========================
 - Supports only UDP for the moment and no TLS
 - Helps you formating the string according to https://tools.ietf.org/html/rfc5424. I am not sure I follow all the standard here but it cover all basic needs and the use of structured data
 
How to use it ?
===============
You can just dot source the script in your own script and then usage is like this :
$syslogClient = Create-SyslogClient "yourserver" 514
"Simple message" | Send-SyslogMessage $syslogClient user Information 
"Simple message with MsgId" | Send-SyslogMessage $syslogClient user Information -MsgId "TEST"
"Message with structured data" | Send-SyslogMessage $syslogClient user Information -MsgId "TEST" -StructuredData @{"test"= @{"a"="1"; "b"="1"}; "test2" = @{"a"="2"; "b"="3"}} -Verbose
 


