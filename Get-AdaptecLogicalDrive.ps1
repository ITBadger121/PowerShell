Function Get-AdaptecLogicalDrive
{
    <#
        .NAME
            Get-AdaptecLogicalDrive

        .SYNOPSIS
            This Function Returns Logical Drive Information From An Adaptec RAID Controller. It Leverages The ARCCONF Utility

        .DESCRIPTION
            This Function Returns Logical Drive Information From An Adaptec RAID Controller. It Leverages The ARCCONF Utility

        .NOTES
            Author          : David Pedley
            Version         : 1.01
        
            Version History:
            1.00            - Initial Release
            1.01            - Added The Ability To Deal With Multiple Logical Drives On The Same Controller

        .EXAMPLE
            #This Example Will Return Logical Drives From An Adaptec RAID Controller (Controller 2) As A Nice PowerShell Object
            Get-AdaptecLogicalDrive -ARCCONFPath C:\ARCCONF.EXE -ControllerID 2
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
            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Return Logical Drive Information On Controller $CID`r`n"
            #Use ARCCONF.EXE To Return Logical Drive Information On The Controller
            [String[]]$LogicalDrives = & $ARCCONFPath GETCONFIG $CID LD
            #We Then Find Out The Logical Drive Numbers That Are Present On The Controller By Using REGEX To Search For All Lines Matching 'Logical Device number \d+'. We Then use Further REGEX To Strip Away Everything Except The 
            #Note The /d+ Will Match One Or More Digits
            [Int[]]$LogicalDriveIDs = [REGEX]::Matches($LogicalDrives, 'Logical Device number \d+').Value -REPLACE 'Logical Device number '
        }
        Catch
        {
            Write-Error "ARCCONF.EXE Failed To Execute"
            Throw $_.Exception
        }

    
        #We Now Start To Iterate Though The $LogicalDriveIDs. This Allows Us To Return Just One Or Several Logical Drives (Depending How Many Are Returned)
        ForEach ($ID In $LogicalDriveIDs)
        {
            Try
            {
                Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Using ARCCONF.EXE To Return Logical Drive $ID From Controller $CID`r`n"
                #Use ARCCONF.EXE To Return Logical Drive Information On The Controller
                [String[]]$LogicalDrives = & $ARCCONFPath GETCONFIG $CID LD $ID
                #We Then Find Out The Logical Drive Numbers That Are Present On The Controller By Using REGEX To Search For All Lines Matching 'Logical Device number \d+'. We Then use Further REGEX To Strip Away Everything Except The 
            }
            Catch
            {
                Write-Error "ARCCONF.EXE Failed To Return Logical Drive $ID From Controller $CID"
                Throw $_.Exception
            }

            #Only Continue If Some Output Was Retrieved
            #We Check This By Looking At The $LogicalDrives Variable. This Includes A Line Similar To 'Logical Device number 0'
            #We Check To Make Sure There Is At Least 1 Logical Drive Available (Just In Case Someone Runs On A System With No Controllers/Drives)
            #We Do This By Using Regex To Match The 'Logical Device number' Line In The $LogicalDrives Variable.
            If (([REGEX]::MATCH($LogicalDrives, 'Logical Device number \d+')).Value)
            {
                Try
                {
                    #Create A PSObject. We Will Use This To Build Up Our Object (Containing Logical Drive Information)
                    $PSObject = New-Object PSObject
                    #Iterate Through Each Line In The ARCCONF Output
                    ForEach ($Line In $LogicalDrives)
                    {
                        #Now We Use Regex To Identify The Logical Drive Information
                        #If The Line Begins With 'Logical Device Number' We Continue
                        If ($Line -MATCH '^Logical Device number')  
                        {
                            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Logical Device Number`r`n"
                            #We Then Add Properties To The $PSObject Creating A Property.
                            #Here We Use Regex To Extract The 'Logical Drive Number' From, The Text
                            #We Use The 'MATCH' Function To Identify And Extract Any Digits '\d+' From The Line Text
                            $PSObject | Add-Member -Name 'Logical Device number' -Value ([REGEX]::MATCH($Line, '\d+')).Value -MemberType NoteProperty -Force

                            #This Is If You Want A Name Value Pair Rather Than Each Column Addressed Separately
                            #Write-Output (New-Object PSObject -Property @{Name='Logical Device number';Value=([REGEX]::MATCH($Line, '\d+')).Value})
                        }
                        #If The Line Begins With 3 Spaces (And Whose Next Character Isnt A Space) '^\s{3}[^ ]' AND If The Line Contains A Colon Followed By A Space '\:\s' AND If The Line Doesnt Contain The Word 'Segment' Followed By One Or More Digits 'Segment \d+' We Continue
                        ElseIf (($Line -MATCH '^\s{3}[^ ]') -AND ($Line -MATCH '\:\s') -AND ($Line -NOTMATCH 'Segment \d+'))
                        {
                            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Logical Device Information Line '$($Line)'`r`n"
                            #We Trim WhiteSpace Off The Start of The String
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
                        #If The Line Begins With 3 Spaces (And Whose Next Character Isnt A Space) '^\s{3}[^ ]' AND If The Line Contains A Colon Followed By A Space '\:\s' AND If The Line DOES Contain The Word 'Segment' Followed By One Or More Digits 'Segment \d+' We Continue
                        ElseIf (($Line -MATCH '^\s{3}[^ ]') -AND ($Line -MATCH '\:\s') -AND ($Line -MATCH 'Segment \d+'))
                        {
                            Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Found Logical Device Sector Information Line '$($Line)'`r`n"
                            #We Use Similar Regex To Split The Line In Two
                            $SplitOutput = $Line.Trim() -SPLIT '(?s)\s{2}.*?\:\s'

                            #We Then Add Properties To The $PSObject
                            $PSObject | Add-Member -Name "Segment Information : $($SplitOutput[0])" -Value $($SplitOutput[1]) -MemberType NoteProperty -Force

                            #This Is If You Want A Name Value Pair Rather Than Each Column Addressed Separately
                            #Write-Output (New-Object PSObject -Property @{Name="Segment Information : $($SplitOutput[0])";Value=$($SplitOutput[1])})
                        }
                    }

                    Write-Verbose "$((Get-Date).ToString($VerboseDateFormat)) : Generating The Results...`r`n"
                    #Finally We Write Out The Object
                    Write-Output $PSObject
                }
                Catch
                {
                    Write-Error "Unable To Parse ARCCONF Output"
                    Throw $_.Exception
                }
            }
            Else #If We Have No ARCCONF Output Throw An Error And Exit
            {
                Write-Error "Failed To Return Logical Drive Information From Controller $CID. Make ARCCONF Supports Your RAID Controller."
                Throw $_.Exception
            }
        }
    }
}