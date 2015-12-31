####################################################################
# PSSyslog.ps1
#
# Simple Syslog client which helps you formating message rfc5424
# for the moment only UDP Syslog is supported
#
# Usage example : 
# $syslogClient = Create-SyslogClient "yourserver" 514
# "Simple message" | Send-SyslogMessage $syslogClient user Information 
# "Simple message with MsgId" | Send-SyslogMessage $syslogClient user Information -MsgId "TEST"
# "Message with structured data" | Send-SyslogMessage $syslogClient user Information -MsgId "TEST" -StructuredData @{"test"= @{"a"="1"; "b"="1"}; "test2" = @{"a"="2"; "b"="3"}} -Verbose
####################################################################



Add-Type -TypeDefinition @"
   public enum SyslogFacility
   {
		kernel,
        user,
	    mail,
	    systemDaemons,
	    security4,
	    syslogd,
        printer,
	    news,
		uucp,
	    clock,
        security10,
	    FTP,
	    NTP,
	    audit,
	    alert,
	    clock2,
	    local0, 
	    local1,
	    local2,
		local3,
	    local4,
	    local5,
	    local6,
	    local7
   }
"@


Add-Type -TypeDefinition @"
   public enum SyslogSeverity
   {
		Emergency,
		Alert,
		Critical,
		Error,
		Warning,
		Notice,
		Information,
		Debug
   }
"@

function Create-SyslogClient
{
	param(
		[string]$server,
		[int]$port
	)

	try
	{
		$UdpClient = New-Object System.Net.Sockets.UdpClient
		$UdpClient.Connect($server,$port)
	}
	catch
	{
		throw "Unable to connect to syslog server $server $_"
	}

	$MySyslogClient = New-Object PSObject
	$MySyslogClient |Add-Member -MemberType NoteProperty -Name UdpSocket -Value $UdpClient
	$MySyslogClient |Add-Member -MemberType NoteProperty -Name ServerName -Value $server
	$MySyslogClient |Add-Member -MemberType NoteProperty -Name Port -Value $port
	
	return $MySyslogClient
}


function Format-SyslogSDName
{
	<#
		.Synopsis
		This is an internal function that takes as input a string an give as output a string matching the Structured data name specification
		which is : 
			SD-NAME         = 1*32PRINTUSASCII; except '=', SP, ']', %d34 (")
			PRINTUSASCII    = %d33-126

		To make things simple any characters which is not allowed is supressed
	#>
	param(
		[string] $inputString
	)
	
	$outputString = ""
	$inputString.ToCharArray() | %{
		if ( ($_ -ge 33) -and ($_ -le 126) -and ($_ -notin 34,']','=') )
		{
			$outputString += $_
		}
	}

	if ($outputString.Length -gt 32)
	{
		$outputString = $outputString.Substring(0,32)
	}

	return $outputString
}


function Send-SyslogMessage
{
	<#
		.Synopsis
		Format a syslog message according to the specification here https://tools.ietf.org/html/rfc5424
		and send it using the SyslogClient object passed as input.

		The header is sent as ASCII according to specification and the body of the message is sent as UTF8

	#>
	param(
		[Parameter(Mandatory=$True)]
		[PSObject] $SyslogClient,
		[Parameter(Mandatory=$True)]
		[SyslogFacility] $facility,
		[Parameter(Mandatory=$True)]
		[SyslogSeverity] $severity,
		[Parameter(Mandatory=$True,ValueFromPipeline=$True)]
		[string] $message, 
		[string] $MsgId = "-", #This is the message ID which will be inserted in the header
		[hashtable] $StructuredData = $null
	)

	if ($SyslogClient.UdpSocket -ne $null)
	{
		#---------------------------------------------------
		# Formating the message

		#this is the space character
		$sp = " " 
	
		#
		# Format the header of the message
		#
	
		#this is how you calculate priority
		[int]$priotityInt = $facility * 8 + $severity 
		$pri ="<$priotityInt>" 
		$version = "1"
		#We send time in UTC because it simplier to format in fact
		$timestamp= (get-date).ToUniversalTime().ToString("yyyy-MM-ddThh:mm:ss.msZ") 
		$hostname = $ENV:COMPUTERNAME
		#The appname part of the header is the name of the executing script
		$appName = split-path $MyInvocation.ScriptName -Leaf
		$procId = [System.Diagnostics.Process]::GetCurrentProcess().Id
		
		#The final header (with trailing space)
		$SyslogMessageHeader = "$pri$version$sp$timestamp$sp$hostname$sp$appName$sp$procId$sp$MsgId$sp"

		#formating the structured data if any
		if (($StructuredData -ne $null) -and ($StructuredData.Keys.Count -gt 0))
		{
			$SyslogStructuredData =""
			$StructuredData.Keys | %{
				$SdId = Format-SyslogSDName $_
				$SdData = ""
				$StructuredDataProperties = $StructuredData[$_]
				if ($StructuredDataProperties.GetType() -ne @{}.GetType())
				{
					throw "Unexpected structured data format"
				}
				$StructuredDataProperties.Keys | %{
					$paramName = Format-SyslogSDName $_
					$paramValue = $StructuredDataProperties[$_]
					$paramValue = $paramValue.Replace("`"","\`"")
					$paramValue = $paramValue.Replace("\","\\")
					$paramValue = $paramValue.Replace("]","\]")
					$SdData += "$sp$paramName=`"$paramValue`""
				}

				$SdElement = "[$SdId$SdData]"
				$SyslogStructuredData += "$SdElement"
			}
			#The final structured data (with trailing space)
			
			$SyslogStructuredData += $sp
		}
		else
		{
			#The final empty structured data (with trailing space)
			$SyslogStructuredData = "-$sp"
		}
		

		#The final message body
		$SyslogMessageBody = "$message"
	
		# /End of formating the message
		#---------------------------------------------------
		


		#---------------------------------------------------
		# Converting message to byte array
		
		$HeaderBytes = [System.Text.Encoding]::ASCII.GetBytes($SyslogMessageHeader);
		$StructuredDataBytes = [System.Text.Encoding]::UTF8.GetBytes($SyslogStructuredData);
		[byte[]]$BomByte =  @(0xEF, 0xBB, 0xBF) #This is the UTF8 BOM spec
		$MessageBytes = $BomByte + [System.Text.Encoding]::UTF8.GetBytes($SyslogMessageBody);
		$bytes = $HeaderBytes + $StructuredDataBytes + $MessageBytes
		Write-Verbose "$SyslogMessageHeader$SyslogStructuredData$SyslogMessageBody"
		# /End of converting message to byte array
		#---------------------------------------------------

		try
		{

			if ($bytes.Length -gt 1472) #with IP and other headers it migh be fragmented 
			{
				Write-Warning "The message is too big and might not be received"
			}

			$sentBytes = $SyslogClient.UdpSocket.Send($bytes, $bytes.Length);
		}
		catch
		{
			throw "unable to send syslog data $_"
		}


	}
	else
	{
		throw "The socket is not initialized"
	}

}
