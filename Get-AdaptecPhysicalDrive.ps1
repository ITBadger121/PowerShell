Function Get-AdaptecPhysicalDrive
{
    <#
        .NAME
            Get-AdaptecPhysicalDrive

        .SYNOPSIS
            This Function Returns Physical Drive Information From An Adaptec RAID Controller. It Leverages The ARCCONF Utility

        .DESCRIPTION
            This Function Returns Physical Drive Information From An Adaptec RAID Controller. It Leverages The ARCCONF Utility

        .NOTES
            Author          : David Pedley
            Version         : 1.00
        
            Version History:
            1.00            - Initial Release

        .EXAMPLE
            #This Example Will Use ARCCONFPath To Return Physical Drives From An Adaptec RAID Controller (Controller 2) As A Nice PowerShell Object
            Get-AdaptecPhysicalDrive -ARCCONFPath C:\ARCCONF.EXE -ControllerID 2

    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][String]$ARCCONFPath, #Path To The ARCCONF.EXE
        [Parameter(Mandatory=$True)][Int[]]$ControllerID, #Output Path Directory. This Also Serves As A Working Directory (For XML SMART Output)
        [String]$VerboseDateFormat = 'yyyy-MM-dd HH.mm:ss' #This Specifies The Date Format For The Verbose Logging
    )

    #Iterate Through $ControllerID's
    ForEach ($CID In $ControllerID)
    {
        Try
        {
            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Return Physical Drive Information On Controller $CID`r`n"
            #Use ARCCONF.EXE To Return Physical Drive Information On The Controller
            [String[]]$PhysicalDrives = & $ARCCONFPath GETCONFIG $CID PD
        }
        Catch
        {
            Write-Error "ARCCONF.EXE Failed To Execute"
            Throw $_.Exception
        }

        #These Next Two ForEach Loops Aim To Product An Array That Contains The Indexed Line locations (Start And End) Of Each Physical Drive In The $PhysicalDrives ARCCONF Output
        #The Issue Is That Unlike ARCCONF LogicalDrives. You Cannot Return A Single Physical Disk, You Can Only Return Them All (Rubbish)
        #So To Overcome This (So Each Drive Can Be Evaluated And Dealt With Separately) We Need To Split Them out
        #We Do This In The Next Few Lines By Identifying The 'Device #' lines In The ARCCONF Output (Indicating The Beginning Of A Section Showing HDD Details)
        #We Then Identify The Line Number That The 'Device #' Begins At And Work Out The End Line (By Looking At The Next Occurrance Of 'Device #' And Noting The Line Number)

        Try
        {
            #Here The Idea Is To Identify The Line Numbers That Each Device ID (Drive) Is Represented In The ARCCONF Output
            #Create A Counter To Identify Line Numbers
            [Int]$Counter = 0
            #We Iterate Though Each Line In The ARCCONF Output
            [Array]$DeviceInformation = ForEach ($Line In $PhysicalDrives)
            {
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Analysing Line $Counter Of ARCCONF Output To Check For Device Details`r`n"
                #If The Line Matches 'Device #\d+' (Device #0) We Build An Object Including The Device ID, Device Name And The Line Number
                If ($Line -MATCH 'Device #\d+')
                {
                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found $($Line.Trim()) At Line $Counter`r`n"
                    #Add The Device Name And Line Count In The Output To The Object
                    Write-Output (New-Object PSObject -Property @{DeviceText=$Line.Trim();DeviceID=[Int]([REGEX]::Match($Line, '\d+')).Value;LineStart=$Counter;LineEnd=$Null})
                }

                #Increment The Counter
                $Counter++
            }

            #Create A Counter To Identify Array Numbers
            [Int]$CurrentLineCounter = 0
            #Iterate Though The Array, Populating The LineEnd Property 
            ForEach ($Item In ($DeviceInformation | Sort-Object LineStart))
            {
                #We Calculate The Index Of The Next Item In The List
                $NextLineCounter = $CurrentLineCounter+1
                #We Set The Current Items LineEnd Value (I.E. Where The Physical Drive Information End) To 1 Less Than LineStart Property For The Next Item In The List
                #If There Is No Next Item In The List (I.E. We Are At the End Of The List), We Set The LineEnd Value To The Total Line Count In The Original $PhysicalDrives Variable Retrieved From ARCCONF
                $Item.LineEnd = $(If ($NextLineCounter -EQ $DeviceInformation.Count) {$PhysicalDrives.Count} Else {($DeviceInformation[$NextLineCounter].Linestart)-1})
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Device $($Item.DeviceText) Starts At Line $($Item.LineStart) And Ends At Line $Item.LineEnd`r`n"
                #Increment The Counter
                $CurrentLineCounter++
            }
        }
        Catch
        {
            Write-Error "Unable To Parse And Separate ARCCONF Physical Drive Output From $CID"
            Throw $_.Exception
        }

        #Only Continue If Some Output Was Retrieved
        #We Check This By Ensurring There Is At least 1 Object In The $DeviceInformation Object
        If ($DeviceInformation.Count -GT 0)
        {
            Try
            {
                #Now We Have An Object ($DeviceInformation) Containing The Start And End Line Numbers In The $PhysicalDrives Multi-String For Each Physcial Drive Attached To The Controller We Start Promoting Properties
                #We Iterate Through The $DeviceInformation, Returning And Processing The Relevent Lines From $PhysicalDrives
                ForEach ($Device In $DeviceInformation)
                {
                    #Create A PSObject. We Will Use This To Build Up Our Object (Containing Physical Drive Information)
                    $PSObject = New-Object PSObject
                    #We Now Iterate Through The Specifc Lines In $PhysicalDrives
                    ForEach ($Line In $PhysicalDrives[$Device.LineStart..$Device.LineEnd])
                    {
                        #Now We Use Regex To Identify The Physical Drive Information
                        If ($Line -MATCH 'Device #\d+')
                        {
                            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Physical Device Number`r`n"
                            #We Then Add Properties To The $PSObject Creating A Property.
                            $PSObject | Add-Member -Name 'Device' -Value $Device.DeviceID -MemberType NoteProperty -Force
                        }
                        #If The Line Begins With 9 Spaces (And Whose Next Character Isnt A Space) '^\s{9}[^ ]' AND If The Line Contains A Colon Followed By A Space '\:\s' We Continue
                        ElseIf (($Line -MATCH '^\s{9}[^ ]') -AND ($Line -MATCH '\:\s'))
                        {
                            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Physical Device Information Line '$($Line)'`r`n"
                            #We Trim WhiteSpace Off The Start Of The String
                            #We Split The Line In 2.
                            #To Do This We Use The Regex #(?s)\s{2}.*?\:\s
                            #To Explain the Above Regex...:
                            #(?s) Match The Remainder Of The Pattern - In This Case The Pattern Is '\s{2}' (2 Spaces). Make Sure This Pattern is Included In The Match
                            #.*? Continue To Match Any Character Multiple Times Until You Reach The Defined Pattern - Also Match This '\:\s' (A Colon Followed By A Space)
                            #As Ever Regex Testers Are You Friend (E.G. https://regex101.com/)
                            $SplitOutput = $Line.Trim() -SPLIT '(?s)\s{2}.*?\:\s'

                            #We Then Add Properties To The $PSObject
                            $PSObject | Add-Member -Name $($SplitOutput[0]) -Value $($SplitOutput[1]) -MemberType NoteProperty -Force

                            #This Is If You Want A Name Value Pair Rather Than Each Column Addressed Separately
                            #Write-Output (New-Object PSObject -Property @{Name=$($SplitOutput[0]);Value=$($SplitOutput[1])})
                        }
                        #If The Line Begins With 12 Spaces (And Whose Next Character Isnt A Space) '^\s{12}[^ ]' AND If The Line Contains A Colon Followed By A Space '\:\s' AND If The Line Contains '  PHY Identifier  ' We Continue.
                        #It Is Important To Note We Search For '  PHY Identifier  ' With At Least 2 Spaces Each Side. This Is So We Dont Accidentally Select The Similarly Named 'Attached PHY Identifier' Property Which Might Have A Different Value
                        ElseIf (($Line -MATCH '^\s{12}[^ ]') -AND ($Line -MATCH '\:\s') -AND ($Line -MATCH '\s{2}PHY Identifier\s{2}'))
                        {
                            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Device PHY Identifier Information Line '$($Line)'`r`n"
                            #We Trim WhiteSpace Off The Start Of The String
                            #We Split The Line In 2.
                            #To Do This We Use The Regex #(?s)\s{2}.*?\:\s
                            #To Explain the Above Regex...:
                            #(?s) Match The Remainder Of The Pattern - In This Case The Pattern Is '\s{2}' (2 Spaces). Make Sure This Pattern is Included In The Match
                            #.*? Continue To Match Any Character Multiple Times Until You Reach The Defined Pattern - Also Match This '\:\s' (A Colon Followed By A Space)
                            #As Ever Regex Testers Are You Friend (E.G. https://regex101.com/)
                            $SplitOutput = $Line.Trim() -SPLIT '(?s)\s{2}.*?\:\s'
                            #Now We Save The Curent PHY Identifier To A Variable. This Is Important As Otherwise When The Rest Of The PHY Details Are Returned, They Will Be Overwritten (Multiple PHY's With The Same Property Names)
                            [Int]$PHYIdentifier = $SplitOutput[1]

                            #We Then Add Properties To The $PSObject
                            #As This Is The First Of possible Several PHY Properties (All With The Same Name). We Use The Current $PHYIdentifier Value To Uniquely Name The Property
                            $PSObject | Add-Member -Name "PHY $PHYIdentifier Information : $($SplitOutput[0])" -Value $($SplitOutput[1]) -MemberType NoteProperty -Force

                            #This Is If You Want A Name Value Pair Rather Than Each Column Addressed Separately
                            #Write-Output (New-Object PSObject -Property @{Name="PHY $PHYIdentifier Information : $($SplitOutput[0])";Value=$($SplitOutput[1])})
                        }
                        #If The Line Begins With 12 Spaces (And Whose Next Character Isnt A Space) '^\s{12}[^ ]' AND If The Line Contains A Colon Followed By A Space '\:\s' We Continue
                        ElseIf (($Line -MATCH '^\s{12}[^ ]') -AND ($Line -MATCH '\:\s'))
                        {
                            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Device Phy Information Line '$($Line)'`r`n"
                            #We Trim WhiteSpace Off The Start Of The String
                            #We Split The Line In 2.
                            #To Do This We Use The Regex #(?s)\s{2}.*?\:\s
                            #To Explain the Above Regex...:
                            #(?s) Match The Remainder Of The Pattern - In This Case The Pattern Is '\s{2}' (2 Spaces). Make Sure This Pattern is Included In The Match
                            #.*? Continue To Match Any Character Multiple Times Until You Reach The Defined Pattern - Also Match This '\:\s' (A Colon Followed By A Space)
                            #As Ever Regex Testers Are You Friend (E.G. https://regex101.com/)
                            $SplitOutput = $Line.Trim() -SPLIT '(?s)\s{2}.*?\:\s'

                            #We Then Add Properties To The $PSObject
                            #As This Is The First Of possible Several PHY Properties (All With The Same Name). We Use The Current $PHYIdentifier Value To Uniquely Name The Property
                            $PSObject | Add-Member -Name "PHY $PHYIdentifier Information : $($SplitOutput[0])" -Value $($SplitOutput[1]) -MemberType NoteProperty -Force

                            #This Is If You Want A Name Value Pair Rather Than Each Column Addressed Separately
                            #Write-Output (New-Object PSObject -Property @{Name="PHY $PHYIdentifier Information : $($SplitOutput[0])";Value=$($SplitOutput[1])})
                        }
                    }

                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Generating The Results...`r`n"
                    #Finally We Write Out The Object
                    Write-Output $PSObject
                }
            }
            Catch
            {
                Write-Error "Unable To Parse ARCCONF Output"
                Throw $_.Exception
            }
        }
        Else
        {
            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : No Physical Drives Found On $CID...`r`n"
        }
    }
}


