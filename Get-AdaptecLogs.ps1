Function Get-AdaptecLogs
{
    <#
        .NAME
            Get-AdaptecLogs

        .SYNOPSIS
            This Function Returns LOG Information From An Adaptec RAID Controller. It Leverages The ARCCONF Utility. It Can Return EVENT, DEVICE Or DEAD Logs.

        .DESCRIPTION
            This Function Returns LOG Information From An Adaptec RAID Controller. It Leverages The ARCCONF Utility. It Can Return EVENT, DEVICE Or DEAD Logs.
            Specifying The Clear Switch WIll Clear The Relevent Logs

        .NOTES
            Author          : David Pedley
            Version         : 1.00
        
            Version History:
            1.00            - Initial Release

        .EXAMPLE
            #This Example Will The ARCCONFPath To Return The DEVICE Logs On Controller 1
            Get-AdaptecLogs -ARCCONFPath C:\ARCCONF.EXE -ControllerID 1 -Device

        .EXAMPLE
            #This Example Will The ARCCONFPath To Return The EVENT Logs On Controller 1
            Get-AdaptecLogs -ARCCONFPath C:\ARCCONF.EXE -ControllerID 1 -Event

        .EXAMPLE
            #This Example Will The ARCCONFPath To Return The DEAD (Drive) Logs On Controller 1
            Get-AdaptecLogs -ARCCONFPath C:\ARCCONF.EXE -ControllerID 1 -Dead
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][String]$ARCCONFPath, #Path To The ARCCONF.EXE
        [Parameter(Mandatory=$True)][Int[]]$ControllerID, #Output Path Directory. This Also Serves As A Working Directory (For XML SMART Output)
        [Parameter(Mandatory=$True, ParameterSetName='DEVICE')][Switch]$DEVICE, #A Switch Which Allows The Script To Return Device Logs
        [Parameter(Mandatory=$True, ParameterSetName='EVENT')][Switch]$EVENT, #A Switch Which Allows The Script To Return Event Logs
        [Parameter(Mandatory=$True, ParameterSetName='DEAD')][Switch]$DEAD, #A Switch Which Allows The Script To Return Dead Drive Logs
        [Parameter(Mandatory=$True, ParameterSetName='DEVICE')][Parameter(ParameterSetName='EVENT')][Parameter(ParameterSetName='DEAD')][Switch]$Clear, #A Switch Which Allows The Script To Clear Specific Logs
        [String]$VerboseDateFormat = 'yyyy-MM-dd HH.mm:ss' #This Specifies The Date Format For The Verbose Logging
    )

    ForEach ($CID In $ControllerID)
    {
        Try
        {
            If ($DEVICE)
            {
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Return DEVICE Logs Stats From Controller $CID`r`n"
                #Use ARCCONF.EXE To Return DEVICE Logs From The Controller
                [String[]]$LOGS = & $ARCCONFPath GETLOGS $CID DEVICE
            }
            ElseIf ($EVENT)
            {
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Return EVENT Logs Stats From Controller $CID`r`n"
                #Use ARCCONF.EXE To Return EVENT Logs From The Controller
                [String[]]$LOGS = & $ARCCONFPath GETLOGS $CID EVENT
            }
            ElseIf ($DEAD)
            {
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Return DEAD Drive Logs Stats From Controller $CID`r`n"
                #Use ARCCONF.EXE To Return DEAD Drive Logs From The Controller
                [String[]]$LOGS = & $ARCCONFPath GETLOGS $CID DEAD
            }
        }
        Catch
        {
            Write-Error "ARCCONF.EXE Failed To Execute"
            Throw $_.Exception
        }

        #Use The Following REGEX Syntax To MATCH EVENT XML
        #(?s)<ControllerLog.*?</ControllerLog>
        #To Explain the Above Regex...:
        #(?s) Match The Remainder Of The Pattern - In This Case The Pattern Is '<ControllerLog'. Make Sure This Pattern is Included In The Match
        #.*? Continue To Match Any Character Multiple Times Until You Reach The Defined Pattern - Also Match This '</ControllerLog>'
        #As Ever Regex Testers Are You Friend (E.G. https://regex101.com/)
        #After Matching The XML Pattern In The ARCCONF Output, Convert The Plain Text XML String To Axtual XML By Using [XML]
        If ($LOGS)
        {
            Try
            {
                #Parse Any Controller Logs And Convert To XML
                $XML = ([XML]([Regex]::Match($LOGS, '(?s)<ControllerLog.*?</ControllerLog>')).Value)
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Controller Logs Have Been Converted To XML Format`r`n"
            }
            Catch
            {
                Write-Error "Failed To Convert ARCCONF Controller Logs To XML On $CID"
                Throw $_.Exception
            }
        }
        Else #If We Have No ARCCONF Output Throw An Error And Exit
        {
            Write-Error "Failed To Return Logs From Controller $CID"
            Throw $_.Exception
        }

        Try
        {
            #Iterate Through Each Physcial Drive Or Event (There Could Be Several) In The $XML.FirstChild Node.
            #The If Statement In The ForEach Loop Could Do With Some Expalining!
            #We Have The If Statement So...
            #If The $DEAD Or $DEVICE Switches Are Set (I.E. We Are Analysing XML From The 'ARCCONF GETLOGS 1 DEAD' Or 'ARCCONF GETLOGS 1 DEVICE' Command), We Look At Data In The $XML.FirstChild.ChildNodes Node
            #However, If The $EVENT Switch Is Set (I.E. We Are Analysing XML From The 'ARCCONF GETLOGS 1 EVENT' Command), The Actual Data Is In A Different XML Location So We Look At Data In The $XML.FirstChild.ChildNodes.event Node
            #This Makes The Loop Reusable (So We Dont Have To Write A Function Or Duplicate Work
            ForEach ($Item In $(If ($DEAD -OR $DEVICE) {$XML.FirstChild.ChildNodes} ElseIf ($EVENT) {$XML.FirstChild.ChildNodes.event}))
            {
                #Create A PSObject. We Will Use This To Build Up Our Object (Containing Error Counters Of Each Drive)
                $PSObject = New-Object PSObject
                #Now Iterate Though Each Error Counter. As We Move Through Each Counter, We Add That Counter Name, Along With Its Value To The $PSObject We Created Earlier.
                ForEach ($Attribute In $Item.Attributes)
                {
                    #Add The Controller ID To The Array
                    $PSObject | Add-Member -Name ControllerID -Value $CID -MemberType NoteProperty -Force
        
                    #If The Attrubute Name Is 'failureReasonCode' We Then Perform A Switch To Lookup The Friendly Error Name. Switch Based On This Page: http://blog.nold.ca/2012/10/arcconf-adaptec-raid-commands.html
                    If ($Attribute.Name -EQ 'failureReasonCode')
                    {
                        #Add The HDD Failure Attribute And Value (These Will Build Up Depending On How Many Attributes Are Present)
                        #To Explain The Switch Statement. We Use The Last Character From The $Attribute.Value String (Just In Case The Error Code Is In HEX (0X02) Rather Than The HEX, 2).
                        #We Use The SubString Method Here To Pull The Last Charater From The String
                        $PSObject | Add-Member -Name $Attribute.Name -Value "$(Switch ($Attribute.Value.SubString($Attribute.Value.Length-1,$Attribute.Value.Length))
                                                                            {
                                                                                '0' {'Unknown Failure'}
                                                                                '1' {'Device Not Ready'}
                                                                                '2' {'Selection Timout'}
                                                                                '3' {'User Marked The Drive Dead'}
                                                                                '4' {'Hardware Error'}
                                                                                '5' {'Bad Block'}
                                                                                '6' {'Retries Failed'}
                                                                                '7' {'No Response From Drive During Discovery'}
                                                                                '8' {'Inquiry Failed'}
                                                                                '9' {'Probe(Test Unit Ready/Start Stop Unit) Failed'}
                                                                                'A' {'0x0A Bus Discovery Failed '} 
                                                                            }) (Error Code: $($Attribute.Value))" -MemberType NoteProperty -Force
                    }
                    Else
                    {
                        #Add The HDD Failure Attribute And Value (These Will Build Up Depending On How Many Attributes Are Present)
                        $PSObject | Add-Member -Name $Attribute.Name -Value $Attribute.Value -MemberType NoteProperty -Force
                    }
                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Detected An Attribute For $($Attribute.Name). Its Value Will Be Returned`r`n"
                }
    
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Generating The Results...`r`n"
                #Write Out The $PSObject. This Is Then Captured By The $Object Array To Be Output Later
                Write-Output $PSObject
            }
        }
        Catch
        {
            Write-Error "Unable To Parse $DriveType XML"
            Throw $_.Exception
        }

        #If The -Clear Switch Is Flagged We Clear The Relevent Logs
        If ($Clear)
        {
            Try
            {
                If ($DEVICE)
                {
                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Clear DEVICE Logs From Controller $CID`r`n"
                    #Use ARCCONF.EXE To Clear DEVICE Logs From The Controller
                    [String[]]$LOGS = & $ARCCONFPath GETLOGS $CID DEVICE CLEAR NOLOGS
                }
                ElseIf ($EVENT)
                {
                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Clear EVENT Logs From Controller $CID`r`n"
                    #Use ARCCONF.EXE To Clear EVENT Logs From The Controller
                    [String[]]$LOGS = & $ARCCONFPath GETLOGS $CID EVENT CLEAR NOLOGS
                }
                ElseIf ($DEAD)
                {
                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Clear DEAD Drive Logs From Controller $CID`r`n"
                    #Use ARCCONF.EXE To Clear DEAD Drive Logs From The Controller
                    [String[]]$LOGS = & $ARCCONFPath GETLOGS $CID DEAD CLEAR NOLOGS
                }
            }
            Catch
            {
                Write-Error "ARCCONF.EXE Failed To Execute"
                Throw $_.Exception
            }
        }
    }
}
