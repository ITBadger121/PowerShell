Function Get-AdaptecSMARTStatistics
{
    <#
        .NAME
            Get-AdaptecSMARTStatistics

        .SYNOPSIS
            This Function Returns SMART Information From An Adaptec RAID Controller. It Leverages The ARCCONF Utility

        .DESCRIPTION
            This Function Returns SMART Information From An Adaptec RAID Controller. It Leverages The ARCCONF Utility

        .NOTES
            Author          : David Pedley
            Version         : 1.01
        
            Version History:
            1.00            - Initial Release
            1.01            - Added Multiple Controller Support And Corrected A Bug Where Only The First SMART Attribute WOuld Be Output

        .EXAMPLE
            #This Example Will The ARCCONFPath To Return The SMART Information For All SATA Drives Attached To Controller 1
            Get-AdaptecSMARTStatistics -ARCCONFPath C:\ARCCONF.EXE -ControllerID 1 -SATA

        .EXAMPLE
            #This Example Will The ARCCONFPath To Return The SMART Information For All SAS Drives Attached To Controller 2
            Get-AdaptecSMARTStatistics -ARCCONFPath C:\ARCCONF.EXE -ControllerID 2 -SAS
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][String]$ARCCONFPath, #Path To The ARCCONF.EXE
        [Parameter(Mandatory=$True)][Int[]]$ControllerID, #Output Path Directory. This Also Serves As A Working Directory (For XML SMART Output)
        [Parameter(Mandatory=$True, ParameterSetName='SATA')][Switch]$SATA, #A Switch Which Allows The Script To Retuyrn SMART Info From SATA Drives
        [Parameter(Mandatory=$True, ParameterSetName='SAS')][Switch]$SAS, #A Switch Which Allows The Script To Retuyrn SMART Info From SAS Drives
        [String]$VerboseDateFormat = 'yyyy-MM-dd HH.mm:ss' #This Specifies The Date Format For The Verbose Logging

    )

    ForEach ($CID In $ControllerID)
    {
        Try
        {
            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Generate SMART Stats On Controller $CID`r`n"
            #Use ARCCONF.EXE To Generate SMART Stats From The Controller
            [String[]]$SMARTStats = & $ARCCONFPath GETSMARTSTATS $CID
        }
        Catch
        {
            Write-Error "ARCCONF.EXE Failed To Execute"
            Throw $_.Exception
        }

        #Use The Following REGEX Syntax To MATCH SATA XML
        #(?s)<SmartStats.*?</SmartStats>
        #To Explain the Above Regex...:
        #(?s) Match The Remainder Of The Pattern - In This Case The Pattern Is '<SmartStats'. Make Sure This Pattern is Included In The Match
        #.*? Continue To Match Any Character Multiple Times Until You Reach The Defined Pattern - Also Match This '</SmartStats>'
        #As Ever Regex Testers Are You Friend (E.G. https://regex101.com/)
        #After Matching The XML Pattern In The ARCCONF Output, Convert The Plain Text XML String To Axtual XML By Using [XML]
        If ($SMARTStats)
        {
            Try
            {
                #Parse Any SATA SMART Stats And Convert To XML
                $SATAXML = ([XML]([Regex]::Match($SMARTStats, '(?s)<SmartStats.*?</SmartStats>')).Value)
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : SMART Stats For SATA Drives Have Been Converted To XML Format`r`n"

                #Parse Any SAS SMART Stats And Convert To XML
                $SASXML = ([XML]([Regex]::Match($SMARTStats, '(?s)<SASSmartStats.*?</SASSmartStats>')).Value)
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : SMART Stats For SAS Drives Have Been Converted To XML Format`r`n"
            }
            Catch
            {
                Write-Error "Failed To Convert ARCCONF SMART Stats To XML On $CID"
                Throw $_.Exception
            }
        }
        Else #If We Have No ARCCONF Output Throw An Error And Exit
        {
            Write-Error "Failed To Return Smart Stats From Controller $CID"
            Throw $_.Exception
        }

        #Next We Figure Out The Drive Type To Return SMART Stats On Based On The ParameterSetName Used In The Function
        If ($SATA)
        {
            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Script Will Return SMART Stats For SATA Drives`r`n"
            #Set The Drive Type To SATA
            [String]$DriveType = 'SATA'
            #Set The SATA XML To A Generic Name
            [XML]$XML = $SATAXML
        }
        ElseIf ($SAS)
        {
            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Script Will Return SMART Stats For SATA Drives`r`n"
            #Set The Drive Type To SAS
            [String]$DriveType = 'SAS'
            #Set The SAS XML To A Generic Name
            [XML]$XML = $SASXML
        }

            Try
            {
            #Iterate Through Each Controller (There Should Only Be One) In The $XML.FirstChild Node
            #Note We Use FirstChild ...Just So We Dont Have To Differentiate Between SAS And SATA Drives
            ForEach ($Controller In $XML.FirstChild)
            {
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Enumerating Controller Information In XML Output`r`n"
                #Iterate Through Each Physcial Drive (There Could Be Several) In The $XML.FirstChild.PhysicalDriveSmartStats Node
                ForEach ($HDDElement In $XML.FirstChild.PhysicalDriveSmartStats)
                {
                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Enumerating Drive Information In XML Output`r`n"
                    #Create A PSObject. We Will Use This To Build Up Our Object (Containing SMART Counters Of Each Drive)
                    $PSObject = New-Object PSObject
                    #Now Iterate Though Each Smart Counter. As We Move Through Each SMART Counter, We Add That Counter, Along With Its Raw Value To The $PSObject We Created Earlier. At The Same Time We Also Add The Current HDD Device And Cahnnel Along With Controller Details From $Controller
                    ForEach ($SMARTAttribute In $HDDElement.Attribute)
                    {
                        Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Enumerating SMART Information Information In XML Output And Building Abn Object`r`n"
                        #Add The Drive Type
                        $PSObject | Add-Member -Name DriveType -Value $DriveType -MemberType NoteProperty -Force
                        #Add The Controller Manufacturer
                        $PSObject | Add-Member -Name ControllerMake -Value $Controller.DeviceVendor -MemberType NoteProperty -Force
                        #Add The Controller Model
                        $PSObject | Add-Member -Name ControllerModel -Value $Controller.DeviceName -MemberType NoteProperty -Force
                        #Add The Controller Serial Number
                        $PSObject | Add-Member -Name ControllerSerialNumber -Value $Controller.SerialNumber -MemberType NoteProperty -Force
                        #Add The HDD Channel
                        $PSObject | Add-Member -Name HDDChannel -Value $HDDElement.Channel -MemberType NoteProperty -Force
                        #Add The HDD Device ID
                        $PSObject | Add-Member -Name HDDID -Value $HDDElement.ID -MemberType NoteProperty -Force
                        #Add The SMART Attribute And Value (These Will Build Up Depending On How Many SMART Attributes Are Present)
                        #To Explain The If Statement Nested In This Add-Member Command!
                        #We Evaluate To See If There Is A 'Status' Property (Exposed On HP SAS Drives). If So We Use The Status Property Value. If Not We Use The Standard RawValue Property Value
                        $PSObject | Add-Member -Name $SMARTAttribute.Name -Value $(If ($SMARTAttribute.Status) {$SMARTAttribute.Status} Else {$SMARTAttribute.RawValue}) -MemberType NoteProperty -Force

                        Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Detected A SMART Attribute For $($SMARTAttribute.Name). Its Value Will Be Returned`r`n"
                    }

                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Generating The Results...`r`n"
                    #Write Out The $PSObject. This Is Then Captured By The $Object Array To Be Output Later
                    Write-Output $PSObject
                }
            }
        }
        Catch
        {
            Write-Error "Unable To Parse $DriveType XML"
            Throw $_.Exception
        }
    }

}

