## This is a fork of Joel Bennett's Growl for Powershell, 
## http://huddledmasses.org/more-growl-for-windows-from-powershell/
## I did some changes to work with newer versions of Growl... as well as I make it easy to install with one line. 

## This is the first version of a Growl module (just dot-source to use in PowerShell 1.0)
## v 1.0 supports a very simple notice, and no callbacks
## v 2.0 supports registering multiple message types
##       supports callbacks
## v 2.1 redesigned to be a module used from apps, rather than it's own "PowerGrowler" app
##
## TODO:
## * Test sending notices to other PCs directly

Set-StrictMode -Version 2
## this is just a default now, you'll have opportunities to override it...
$script:appName = "PowerGrowler"
$defaultIcon = "$PSScriptRoot\default.png"
if(!(Test-Path $defaultIcon)){
	write-host "Downloading the default icon for Send-Growl in $defaultIcon"
	(new-object Net.WebClient).DownloadFile("http://growl.info/images/growlicons/Growl_256x256.png", $defaultIcon)
}


function Get-GrowlPath {
   if(!(Test-Path HKCU:\Software\Growl)){
      return $null
   }
   return "$(Split-Path (gp HKCU:\Software\Growl).'(default)')"
}

[Reflection.Assembly]::LoadFrom("$(Get-GrowlPath)\Growl.Connector.dll") | Out-Null
if(!(Test-Path Variable:Global:PowerGrowlerNotices)) {
   $global:PowerGrowlerNotices = @{}
}

## We can safely recreate this, it doesn't store much
$script:PowerGrowler = New-Object "Growl.Connector.GrowlConnector"


function Register-GrowlType {
#.Synopsis
#  Register a new Type name for growl notices from PowerGrowl
#.Description
#  Creates a new type name that can be used for sending growl notices
#.Parameter AppName
#  The name of the application you want to register as
#.Parameter Name
#  The type name to be used sending growls
#.Parameter DisplayName
#  The test to use for display (defaults to use the same value as the type name)
#.Parameter Icon
#  Overrides the default icon of the message (accepts .ico, .png, .bmp, .jpg, .gif etc)
#.Parameter MachineName
#  The name of a remote machine to register remotely instead of locally.
#.Parameter Priority
#  Overrides the default priority of the message (use sparingly)
#.Example
#  Register-GrowlType "PoshTwitter" "Command Completed"
#  
#  Registers the type "Command Completed," using the default icon, for sending notifications to the local PC
#
PARAM(
   [Parameter(Mandatory=$true,Position=0)]
   [String]$AppName
,
   [Parameter(Mandatory=$true,Position=1)]
   [String]$Name
,
   [Parameter(Mandatory=$false,Position=5)]
   [String]$Icon = "$defaultIcon"
,
   [Parameter(Mandatory=$false,Position=6)]
   [String]$DisplayName = $Name
,
   [Parameter(Mandatory=$false,Position=7)]
   [String]$MachineName
,
   [Parameter(Mandatory=$false)]
   [String]$AppIcon
)
  
   [Growl.Connector.NotificationType]$Notice = $Name
   $Notice.DisplayName = $DisplayName
   
   if(!(Test-Path $Icon) -and ($Icon -eq $defaultIcon)){
      write-host "Downloading the default icon for Send-Growl in $defaultIcon"
     (new-object Net.WebClient).DownloadFile("http://growl.info/images/growlicons/Growl_256x256.png", $defaultIcon)
   }
   
   $Notice.Icon = Convert-Path (Resolve-Path $Icon)
	
   if($MachineName) {
      $Notice.MachineName = $MachineName
   }
   if(!$global:PowerGrowlerNotices.Contains($AppName)) {
      $global:PowerGrowlerNotices.Add( $AppName, ([Growl.Connector.Application]$AppName) )

      $global:PowerGrowlerNotices.$AppName = Add-Member -input $global:PowerGrowlerNotices.$AppName -Name Notices -Type NoteProperty -Value (New-Object hashtable) -Passthru
	  if(!$AppIcon){
		$global:PowerGrowlerNotices.$AppName.Icon = Convert-Path (Resolve-Path $defaultIcon)
	  }else{
		$global:PowerGrowlerNotices.$AppName.Icon = Convert-Path (Resolve-Path $AppIcon)
	  }
   }
   if(!$global:PowerGrowlerNotices.$AppName.Notices.ContainsKey($Name)){
	  $global:PowerGrowlerNotices.$AppName.Notices.Add( $Name, $Notice )
   }
   $script:PowerGrowler.Register( $global:PowerGrowlerNotices.$AppName , [Growl.Connector.NotificationType[]]@($global:PowerGrowlerNotices.$AppName.Notices.Values) )
}


function Set-GrowlPassword { 
#.Synopsis
#  Set the Growl password
#.Description
#  Set the password and optionally, the encryption algorithm, for communicating with Growl
#.Parameter Password
#  The password for Growl
#.Parameter Encryption
#  The algorithm to be used for encryption (defaults to AES)
#.Parameter KeyHash
#  The algorithm to be used for key hashing (defaults to SHA1)
PARAM( 
   [Parameter(Mandatory=$true,Position=0)]
   [String]$Password
,
   [Parameter(Mandatory=$false,Position=1)]
   [ValidateSet( "AES", "DES", "RC2", "TripleDES", "PlainText" )]
   [String]$Encryption = "AES"
,   
   [Parameter(Mandatory=$false,Position=2)]
   [ValidateSet( "MD5", "SHA1", "SHA256", "SHA384", "SHA512" )]
   [String]$KeyHash = "SHA1"
)   
   $script:PowerGrowler.EncryptionAlgorithm = [Growl.Connector.Cryptography+SymmetricAlgorithmType]::"$Encryption"
   $script:PowerGrowler.KeyHashAlgorithm = [Growl.Connector.Cryptography+SymmetricAlgorithmType]::"$KeyHash"
   $script:PowerGrowler.Password = $Password
}

## Register the "PowerGrowler" "Default" notice so everything works out of the box
Register-GrowlType $script:AppName "Default" -appIcon $defaultIcon

function Register-GrowlCallback {
#.Synopsis
#  Register a script to be called when each notice is finished. 
#.Description
#  Registers a scriptblock as a handler for the NotificationCallback event. You should accept two parameters, a Growl.Connector.Response and a Growl.Connector.CallbackData object.
#  
#  The NotificationCallback only happens when a callback is requested, which in this Growl library only happens if you pass both CallbackData and CallbackType to the Send-Growl function.
#.Example
#  Register-GrowlCallback { PARAM( $response, $context )
#    Write-Host "Response $($response|out-string)" -fore Cyan
#    Write-Host "Context $($context|fl|out-string)" -fore Green
#    Write-Host $("Response Type: {0}`nNotification ID: {1}`nCallback Data: {2}`nCallback Data Type: {3}`n" -f $context.Result, $context.NotificationID, $context.Data, $context.Type) -fore Yellow
#  }
#
#  Registers an informational debugging-style handler. 
#
PARAM(
[Parameter(Mandatory=$true)]
[Scriptblock]$Handler
)
   Register-ObjectEvent $script:PowerGrowler NotificationCallback -Action $Handler
}

function Send-Growl {
[CmdletBinding(DefaultParameterSetName="DataCallback")]
#.Synopsis
#  Send a growl notice
#.Description
#  Send a growl notice with the scpecified values
#.Parameter Caption
#  The short caption to display
#.Parameter Message
#  The message to send (most displays will resize to accomodate)
#.Parameter NoticeType
#  The type of notice to send. This MUST be the name of one of the registered types, and senders should bear in mind that each registered type has user-specified settings, so you should not abuse the types, but create your own for messages that will recur.
#  For example, the user settings allow certain messages to be disabled, set to a different "Display", or to have their Duration and Stickyness changed, as well as have them be Forwarded to another device, have Sounds play, and set different priorities.
#.Parameter Icon
#  Overrides the default icon of the message (accepts .ico, .png, .bmp, .jpg, .gif etc)
#.Parameter Priority
#  Overrides the default priority of the message (use sparingly)
#.Example
#  Send-Growl "Greetings" "Hello World!"
#
#  The Hello World of Growl.
#.Example
#  Send-Growl "You've got Mail!" "Message for you sir!" -icon ~\Icons\mail.png
#
#  Displays a message with a couple of movie quotes and a mail icon.
#
PARAM (
   [Parameter(Mandatory=$true, Position=0)]
   [ValidateScript( {$global:PowerGrowlerNotices.Contains($AppName)} )]
   [string]$AppName
,
   [Parameter(Mandatory=$true, Position=1)][Alias("Type")]   
   [ValidateScript( {$global:PowerGrowlerNotices.$AppName.Notices.ContainsKey($_)} )]   
   [string]$NoticeType
,
   [Parameter(Mandatory=$true, Position=2)]
   [string]$Caption
,
   [Parameter(Mandatory=$true, Position=3)]
   [string]$Message
,
   [Parameter(Mandatory=$true, Position=4, ParameterSetName="UrlCallback")]
   [Uri]$Url
,  
   [Parameter(Mandatory=$false, Position=4, ParameterSetName="DataCallback")]
   [string]$CallbackData
,  
   [Parameter(Mandatory=$false, Position=5, ParameterSetName="DataCallback")]
   [string]$CallbackType
,
   [string]$Icon
,
   [Growl.Connector.Priority]$Priority = "Normal" 
)

   $notice = New-Object Growl.Connector.Notification $appName, $NoticeType, (Get-Date).Ticks.ToString(), $caption, $Message
   
   if($Icon) { $notice.Icon = Convert-Path (Resolve-Path $Icon) }
   if($Priority) { $notice.Priority = $Priority }
   
   if($DebugPreference -gt "SilentlyContinue") { Write-Output $notice }
   if( Test-Path Variable:Local:Url ) {
      $contextData = $(if(Test-Path Variable:Local:CallbackData){$CallbackData}else{$Url.ToString()})
      $contextType = $(if(Test-Path Variable:Local:CallbackType){$CallbackType}else{"$NoticeType+Url"})
      $context = new-object Growl.Connector.CallbackContext($contextData, $contextType)
      $script:PowerGrowler.Notify($notice, $context)
   } elseif( (Test-Path Variable:Local:CallbackData) -and !$CallbackType ) {
	  $context = new-object Growl.Connector.CallbackContext($CallbackData)
      $script:PowerGrowler.Notify($notice, $context)
   } elseif( (Test-Path Variable:Local:CallbackData) -and (Test-Path Variable:Local:CallbackType) ) {
      $contextData = $CallbackData
      $contextType = $CallbackType
	  $context = new-object Growl.Connector.CallbackContext($contextData, $contextType)
      $script:PowerGrowler.Notify($notice, $context)
   } else {          
      $script:PowerGrowler.Notify($notice)
   }
}

Export-ModuleMember -Function Send-Growl, Set-GrowlPassword, Register-GrowlCallback, Register-GrowlType, Get-GrowlPath
